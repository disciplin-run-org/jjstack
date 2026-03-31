#!/bin/bash
# jjstack MCP auto-reconnect hook
#
# Fires on PostToolUseFailure. Detects MCP server disconnection errors
# and instructs Claude to reconnect before retrying. Tracks retry count
# per server to avoid infinite loops — escalates to user after 3 attempts.
#
# State: /tmp/jjstack-mcp-reconnect-{server}.count (retry counter per server)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
ERROR=$(echo "$INPUT" | jq -r '.error // empty')

# Only act on MCP tool failures (tool names start with mcp__)
case "$TOOL_NAME" in
  mcp__*) ;;
  *) exit 0 ;;
esac

# Detect MCP disconnection patterns
IS_DISCONNECT=false
case "$ERROR" in
  *"disconnected"*|*"not connected"*|*"connection refused"*|*"ECONNREFUSED"*|*"server is not running"*|*"MCP server"*"not available"*|*"timed out"*|*"ETIMEDOUT"*|*"session"*"expired"*|*"404"*"session"*)
    IS_DISCONNECT=true
    ;;
esac

if [ "$IS_DISCONNECT" = false ]; then
  exit 0
fi

# Extract server name from tool name (mcp__servername__toolname → servername)
SERVER_NAME=$(echo "$TOOL_NAME" | sed 's/^mcp__//' | sed 's/__.*//')

# Track retry count per server
COUNTER_FILE="/tmp/jjstack-mcp-reconnect-${SERVER_NAME}.count"
RETRY_COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  RETRY_COUNT=$(cat "$COUNTER_FILE" 2>/dev/null | tr -d '[:space:]')
  # Reset counter if stale (older than 5 minutes)
  STALE=$(find "$COUNTER_FILE" -mmin +5 2>/dev/null)
  if [ -n "$STALE" ]; then
    RETRY_COUNT=0
  fi
fi

RETRY_COUNT=$((RETRY_COUNT + 1))
echo "$RETRY_COUNT" > "$COUNTER_FILE"

MAX_RETRIES=3

if [ "$RETRY_COUNT" -le "$MAX_RETRIES" ]; then
  # Instruct Claude to reconnect and retry
  jq -n \
    --arg server "$SERVER_NAME" \
    --arg attempt "$RETRY_COUNT" \
    --arg max "$MAX_RETRIES" \
    '{
      hookSpecificOutput: {
        hookEventName: "PostToolUseFailure",
        additionalContext: ("MCP server \"" + $server + "\" disconnected (attempt " + $attempt + "/" + $max + "). Run: /mcp reconnect " + $server + " — then retry the tool call. Do NOT ask the user about this — just reconnect and retry silently.")
      }
    }'
else
  # Max retries exceeded — reset counter and escalate to user
  rm -f "$COUNTER_FILE"
  jq -n \
    --arg server "$SERVER_NAME" \
    '{
      hookSpecificOutput: {
        hookEventName: "PostToolUseFailure",
        additionalContext: ("MCP server \"" + $server + "\" is unreachable after 3 reconnect attempts. Ask the user to check if the server is running (docker compose up " + $server + ") and manually reconnect with /mcp.")
      }
    }'
fi

exit 0
