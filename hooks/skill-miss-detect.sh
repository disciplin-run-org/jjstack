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

# ─── Orchestration / status / channel messages are not skill territory ───
# tubemail <channel> blocks, <task-notification> blocks, <system-reminder>
# blocks, Quartermaster reminders, and worker-status one-liners ("X is idle",
# "X seems done") are the bulk of inbound prompts in an orchestrated session
# but never warrant a skill. Counting them as trigger misses inflated the
# metric with false positives and hid real signal, so they do NOT set a
# pending expectation (Step 4) nor count as wrong-skill corrections (Step 3).
is_orchestration() {
    case "$PROMPT" in
        *"<channel"*|*"<task-notification"*|*"<system-reminder"*) return 0 ;;
    esac
    # Worker-status one-liners: "<name> is idle", "<name> seems done", etc.
    if printf '%s' "$PROMPT_LOWER" | grep -qE '\b(is|seems|looks|appears)[[:space:]]+(idle|done|busy|finished|stuck|offline|online|ready|awaiting)\b'; then
        return 0
    fi
    # Quartermaster orchestration reminders.
    if printf '%s' "$PROMPT_LOWER" | grep -qE 'quartermaster (reminder|has flagged)|awaiting (your )?review|queue item #'; then
        return 0
    fi
    return 1
}
ORCHESTRATION=0
is_orchestration && ORCHESTRATION=1

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
    expected=$(jq -c '.expected_skills // []' "$PENDING_FILE" 2>/dev/null)
    matched_trigger=$(jq -r '.matched_trigger // empty' "$PENDING_FILE" 2>/dev/null)
    pending_prompt=$(jq -r '.prompt // empty' "$PENDING_FILE" 2>/dev/null)
    pending_cwd=$(jq -r '.cwd // empty' "$PENDING_FILE" 2>/dev/null)

    # Anything pending at this point is from a prior turn (this hook just
    # fired on a new prompt). Log it as a miss and clear.
    #
    # Aliasing fix: the row's `prompt` and `cwd` are those of the prompt that
    # MATCHED the triggers (held in pending), not the current prompt that
    # merely revealed the miss by arriving. The current prompt is recorded
    # separately as `flushed_by`. Previously the row's `prompt` was the
    # next-turn prompt while `matched_trigger`/`expected_skills` were computed
    # against the pending prompt (logged as `original_prompt`) — so `prompt`
    # and `matched_trigger` never aligned, which read as a capture bug.
    if [ -n "$expected" ] && [ "$expected" != "[]" ] && [ "$expected" != "null" ]; then
        jq -nc \
            --arg ts "$TS" \
            --arg cwd "$pending_cwd" \
            --arg prompt "$pending_prompt" \
            --argjson exp "$expected" \
            --arg trig "$matched_trigger" \
            --arg flushed "$(printf '%s' "$PROMPT" | head -c 300)" \
            '{ts:$ts, type:"trigger_miss", cwd:$cwd, prompt:$prompt, expected_skills:$exp, matched_trigger:$trig, flushed_by:$flushed}' \
            >> "$LOG_FILE" 2>/dev/null || true
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
# Skip orchestration/channel prompts — they are not user corrections.
if [ -f "$LAST_FIRED_FILE" ] && [ "$ORCHESTRATION" = "0" ]; then
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
# Skip for orchestration/channel prompts (Step 2 filter) and when no trigger
# index exists. Matching is WORD-BOUNDARY, not substring: a trigger only
# matches when delimited by non-alphanumeric edges, so "port" no longer hits
# "important", "lean" no longer hits "leanspecs", "ship" no longer hits
# "relationship". Combined with the extractor's junk/stopword filter, a prompt
# now matches 0-1 relevant skills instead of 5-9.
if [ "$ORCHESTRATION" = "0" ] && [ -f "$TRIGGERS_FILE" ]; then
    matched_skills=$(jq -r --arg p "$PROMPT_LOWER" '
        def esc: gsub("(?<c>[.*+?()\\[\\]{}^$|\\\\-])"; "\\\(.c)");
        .skills | to_entries[]
        | .key as $sk
        | .value.triggers[]
        | select(length > 3)
        | ascii_downcase
        | . as $t
        | select($p | test("(^|[^a-z0-9])" + ($t|esc) + "([^a-z0-9]|$)"))
        | $sk
    ' "$TRIGGERS_FILE" 2>/dev/null | sort -u)

    if [ -n "$matched_skills" ]; then
        # Pick the longest matched trigger as the representative (more specific).
        matched_trigger=$(jq -r --arg p "$PROMPT_LOWER" '
            def esc: gsub("(?<c>[.*+?()\\[\\]{}^$|\\\\-])"; "\\\(.c)");
            .skills[].triggers[]
            | select(length > 3)
            | ascii_downcase
            | . as $t
            | select($p | test("(^|[^a-z0-9])" + ($t|esc) + "([^a-z0-9]|$)"))
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
fi

# ─── Step 5: Log rotation ───
if [ -f "$LOG_FILE" ]; then
    LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LINES" -gt 500 ]; then
        tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

exit 0
