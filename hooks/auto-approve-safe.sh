#!/bin/bash
# jjstack auto-approve hook — smart permission gate using Claude Haiku.
#
# Three-tier risk assessment:
#   1. Read-only tools (Read, Glob, Grep, etc.) → always approve
#   2. Bash commands → Claude Haiku rates risk as LOW/MEDIUM/HIGH
#      - LOW  → auto-approve
#      - MEDIUM/HIGH → defer to user
#   3. Fallback heuristic if API unavailable → block dangerous patterns, allow rest
#
# Requires: jq, curl
# API key: set ANTHROPIC_API_KEY env var, or store in ~/.claude/anthropic_api_key

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

allow() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "allow" }
    }
  }'
  exit 0
}

defer() {
  # Exit 0 = let the normal permission dialog appear
  exit 0
}

# ── Non-Bash tools: always allow ─────────────────────────────────────────────
case "$TOOL_NAME" in
  Read|Glob|Grep|Search|WebSearch|WebFetch)
    allow
    ;;
esac

# ── Bail out if not a Bash command ───────────────────────────────────────────
[ "$TOOL_NAME" != "Bash" ] && defer
[ -z "$COMMAND" ] && defer

# ── Get API key ───────────────────────────────────────────────────────────────
API_KEY="${ANTHROPIC_API_KEY}"
if [ -z "$API_KEY" ]; then
  KEY_FILE="$HOME/.claude/anthropic_api_key"
  if [ -f "$KEY_FILE" ]; then
    # Warn if key file is readable by others (should be 600)
    PERMS=$(stat -c '%a' "$KEY_FILE" 2>/dev/null || stat -f '%Lp' "$KEY_FILE" 2>/dev/null)
    case "$PERMS" in
      600|400) ;; # OK
      *) chmod 600 "$KEY_FILE" 2>/dev/null || true ;;
    esac
    API_KEY=$(cat "$KEY_FILE" 2>/dev/null | tr -d '[:space:]')
  fi
fi

if [ -z "$API_KEY" ]; then
  # No key — fail-closed: only allow clearly safe read-only commands
  # Reject commands with shell metacharacters that could chain dangerous operations
  echo "$COMMAND" | grep -qE '[;&|`$]\(' && defer
  echo "$COMMAND" | grep -qE '\|' && defer
  SAFE_READONLY='^\s*(ls|cat|head|tail|wc|file|stat|which|type|echo|printf|date|pwd|whoami|uname|id|env|printenv|git (status|log|diff|show|branch|tag|remote|rev-parse|describe))\b'
  echo "$COMMAND" | grep -qE "$SAFE_READONLY" && allow
  defer
fi

# ── Build JSON payload safely using jq ───────────────────────────────────────
PAYLOAD=$(jq -n \
  --arg cmd "$COMMAND" \
  '{
    model: "claude-haiku-4-5-20251001",
    max_tokens: 10,
    system: "You are a shell command safety rater. Respond with exactly one word: LOW, MEDIUM, or HIGH.",
    messages: [{
      role: "user",
      content: ("Rate the risk of this shell command being run on a developer local machine:\n\n" + $cmd)
    }]
  }')

# ── Call Claude Haiku ─────────────────────────────────────────────────────────
RESPONSE=$(curl -s --max-time 6 https://api.anthropic.com/v1/messages \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" 2>/dev/null)

RISK=$(echo "$RESPONSE" | jq -r '.content[0].text // ""' | grep -oE 'LOW|MEDIUM|HIGH' | head -1 | tr '[:lower:]' '[:upper:]')

case "$RISK" in
  LOW)
    allow
    ;;
  MEDIUM|HIGH)
    defer
    ;;
  *)
    # API call failed or unexpected response — fail-closed: only allow safe read-only commands
    # Reject commands with shell metacharacters that could chain dangerous operations
    echo "$COMMAND" | grep -qE '[;&|`$]\(' && defer
    echo "$COMMAND" | grep -qE '\|' && defer
    SAFE_READONLY='^\s*(ls|cat|head|tail|wc|file|stat|which|type|echo|printf|date|pwd|whoami|uname|id|env|printenv|git (status|log|diff|show|branch|tag|remote|rev-parse|describe))\b'
    echo "$COMMAND" | grep -qE "$SAFE_READONLY" && allow
    defer
    ;;
esac
