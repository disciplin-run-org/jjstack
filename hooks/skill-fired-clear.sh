#!/bin/bash
# jjstack skill-fired-clear hook — PreToolUse hook on the Skill tool.
#
# Two jobs:
#   1. Record the firing skill in ~/.jjstack/skill-last-fired.json so the
#      next UserPromptSubmit hook can detect wrong-skill corrections.
#   2. If the firing skill matches a pending trigger expectation, clear the
#      pending state — the model fired correctly.
#
# Never blocks the Skill invocation. Exit 0 always.

set -uo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Skill" ] || exit 0

# Skill tool input shape: {skill: "name", args: "..."}
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
[ -z "$SKILL_NAME" ] && exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TS_EPOCH=$(date -u +%s)

STATE_DIR="${JJSTACK_STATE_DIR:-$HOME/.jjstack}"
PENDING_FILE="$STATE_DIR/skill-trigger-pending.json"
LAST_FIRED_FILE="$STATE_DIR/skill-last-fired.json"
mkdir -p "$STATE_DIR"

# Always record the firing skill.
jq -nc \
    --arg s "$SKILL_NAME" \
    --arg ts "$TS" \
    --argjson at_epoch "$TS_EPOCH" \
    '{skill:$s, at:$ts, at_epoch:$at_epoch}' \
    > "$LAST_FIRED_FILE" 2>/dev/null || true

# Clear pending if the firing skill matches an expected one.
if [ -f "$PENDING_FILE" ]; then
    expected_match=$(jq -r --arg s "$SKILL_NAME" \
        '.expected_skills // [] | index($s)' \
        "$PENDING_FILE" 2>/dev/null)
    if [ -n "$expected_match" ] && [ "$expected_match" != "null" ]; then
        rm -f "$PENDING_FILE"
    fi
fi

exit 0
