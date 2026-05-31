#!/bin/bash
# jjstack skill-miss-detect hook — UserPromptSubmit hook that captures three
# kinds of signal about skill auto-routing failure:
#
#   1. trigger_miss     — prompt N matched a skill's trigger phrases, but no
#                          Skill tool fired in turn N before turn N+1 arrived.
#   2. user_correction  — current prompt is "/missed <skill>" — explicit
#                          ground truth from the user.
#   3. wrong_skill      — current prompt looks like a correction of a
#                          recently-fired skill ("no", "use /X", "wrong skill").
#
# Output: ~/.jjstack/skill-misses.jsonl (one event per line, rotated at 500)
# Schema per row: {ts, type, ...type-specific fields, cwd, prompt}
#
# State files (single-object, overwritten):
#   ~/.jjstack/skill-trigger-pending.json — current pending expectation
#   ~/.jjstack/skill-last-fired.json      — last Skill fired (written by
#                                            skill-fired-clear.sh)
#
# Philosophy: pure observation, never blocks the prompt. Exit 0 always.

set -uo pipefail

INPUT=$(cat)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TS_EPOCH=$(date -u +%s)

# UserPromptSubmit input shape: {prompt, cwd, session_id, ...}
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

STATE_DIR="${JJSTACK_STATE_DIR:-$HOME/.jjstack}"
TRIGGERS_FILE="$STATE_DIR/skill-triggers.json"
PENDING_FILE="$STATE_DIR/skill-trigger-pending.json"
LAST_FIRED_FILE="$STATE_DIR/skill-last-fired.json"
LOG_FILE="$STATE_DIR/skill-misses.jsonl"
mkdir -p "$STATE_DIR"

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

log_event() {
    # log_event <type> <json-fragment-of-extra-fields>
    local type="$1"
    local extra="$2"
    local prompt_truncated
    prompt_truncated=$(printf '%s' "$PROMPT" | head -c 300)
    jq -nc \
        --arg ts "$TS" \
        --arg type "$type" \
        --arg cwd "$CWD" \
        --arg prompt "$prompt_truncated" \
        --argjson extra "$extra" \
        '{ts:$ts, type:$type, cwd:$cwd, prompt:$prompt} * $extra' \
        >> "$LOG_FILE" 2>/dev/null || true
}

# ─── Step 1: Check for an unresolved pending expectation from the previous turn ───
# A pending expectation that survives until the NEXT user prompt means: we
# matched triggers, no Skill fired between turns. Log it.
if [ -f "$PENDING_FILE" ]; then
    pending_ts=$(jq -r '.set_at_epoch // 0' "$PENDING_FILE" 2>/dev/null)
    expected=$(jq -c '.expected_skills // []' "$PENDING_FILE" 2>/dev/null)
    matched_trigger=$(jq -r '.matched_trigger // empty' "$PENDING_FILE" 2>/dev/null)
    pending_prompt=$(jq -r '.prompt // empty' "$PENDING_FILE" 2>/dev/null)

    # Anything pending at this point is from a prior turn (this hook just
    # fired on a new prompt). Log it as a miss and clear.
    if [ -n "$expected" ] && [ "$expected" != "[]" ] && [ "$expected" != "null" ]; then
        log_event "trigger_miss" "$(jq -nc \
            --argjson exp "$expected" \
            --arg trig "$matched_trigger" \
            --arg pp "$pending_prompt" \
            '{expected_skills:$exp, matched_trigger:$trig, original_prompt:$pp}')"
    fi
    rm -f "$PENDING_FILE"
fi

# ─── Step 2: /missed <skill> — explicit user correction ───
# Exclusive: when /missed fires, skip wrong-skill detection and trigger
# matching. /missed is ground truth from the user.
if echo "$PROMPT" | grep -qE '^[[:space:]]*/missed( |$)'; then
    skill_arg=$(echo "$PROMPT" | sed -E 's|^[[:space:]]*/missed[[:space:]]+([^[:space:]]+).*|\1|; t; d')
    log_event "user_correction" "$(jq -nc --arg s "$skill_arg" '{user_pointed_to:$s, source:"slash_missed"}')"
    exit 0
fi

# ─── Step 3: Wrong-skill correction pattern ───
# Look for negative-feedback patterns that follow a recently-fired skill.
if [ -f "$LAST_FIRED_FILE" ]; then
    last_skill=$(jq -r '.skill // empty' "$LAST_FIRED_FILE" 2>/dev/null)
    last_fired_epoch=$(jq -r '.at_epoch // 0' "$LAST_FIRED_FILE" 2>/dev/null)
    age=$((TS_EPOCH - last_fired_epoch))
    # Only consider corrections within the last 5 minutes.
    if [ -n "$last_skill" ] && [ "$age" -lt 300 ]; then
        # Detect patterns. False positives tolerated.
        if echo "$PROMPT_LOWER" | grep -qE '^(no[[:space:]]|nope|wrong[[:space:]]|that.?s not|not the right|use[[:space:]]+/)' \
           || echo "$PROMPT_LOWER" | grep -qE '(should have used|shouldn.?t you (have )?use|wrong skill|we have a skill for)' \
           || echo "$PROMPT" | grep -qE '/[a-z][a-z0-9-]+' ; then
            # Try to extract a referenced skill name.
            ref_skill=$(echo "$PROMPT" | grep -oE '/[a-z][a-z0-9-]+' | head -1 | sed 's|^/||')
            log_event "wrong_skill" "$(jq -nc \
                --arg prev "$last_skill" \
                --arg ref "$ref_skill" \
                '{previous_skill:$prev, referenced_skill:$ref}')"
        fi
    fi
fi

# ─── Step 4: Trigger-phrase matching (set new pending) ───
[ ! -f "$TRIGGERS_FILE" ] && exit 0

# Find skills whose trigger phrases appear in the lowercased prompt. Use
# substring matching against the trigger (also lowercased). Skip very-short
# triggers (≤3 chars) to reduce noise.
matched_skills=$(jq -r --arg p "$PROMPT_LOWER" '
    .skills | to_entries[]
    | .key as $sk
    | .value.triggers[]
    | select(length > 3)
    | ascii_downcase
    | select(. as $t | $p | contains($t))
    | $sk
' "$TRIGGERS_FILE" 2>/dev/null | sort -u)

if [ -n "$matched_skills" ]; then
    # Pick the longest matched trigger as the representative (more specific).
    matched_trigger=$(jq -r --arg p "$PROMPT_LOWER" '
        .skills[].triggers[]
        | select(length > 3)
        | ascii_downcase
        | select(. as $t | $p | contains($t))
    ' "$TRIGGERS_FILE" 2>/dev/null | sort -u | awk '{print length, $0}' | sort -rn | head -1 | cut -d' ' -f2-)

    expected_json=$(printf '%s\n' "$matched_skills" | jq -R . | jq -s .)

    jq -nc \
        --arg ts "$TS" \
        --argjson set_at_epoch "$TS_EPOCH" \
        --argjson exp "$expected_json" \
        --arg trig "$matched_trigger" \
        --arg cwd "$CWD" \
        --arg prompt "$(printf '%s' "$PROMPT" | head -c 300)" \
        '{set_at:$ts, set_at_epoch:$set_at_epoch, expected_skills:$exp, matched_trigger:$trig, cwd:$cwd, prompt:$prompt}' \
        > "$PENDING_FILE" 2>/dev/null || true
fi

# ─── Step 5: Log rotation ───
LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
if [ "$LINES" -gt 500 ]; then
    tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

exit 0
