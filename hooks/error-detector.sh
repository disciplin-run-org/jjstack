#!/bin/bash
# jjstack error-detector hook — records failed Bash commands to a JSONL log so
# recurring failure patterns can be surfaced later and promoted to guidance.
#
# Fires on PostToolUse with matcher Bash. The Bash tool itself "succeeds"
# whenever it runs a command; a non-zero exit from the command is reported
# inside tool_response. We probe multiple field names defensively because the
# tool_response schema has varied across Claude Code versions.
#
# Output: $HOME/.jjstack/command-failures.jsonl (rotated at 500 entries)
# Schema: {ts, cwd, command, exit_code, interrupted, stderr}
#
# Privacy: tool output may contain sensitive strings (paths, env values,
# API error bodies). This hook is for a personal dev machine. Do NOT enable
# in shared contexts without reviewing what lands in the log.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" = "Bash" ] || exit 0

# Try multiple field names — schema has changed between Claude Code versions.
EXIT_CODE=$(echo "$INPUT" | jq -r '
  .tool_response.exit_code //
  .tool_response.returncode //
  .tool_response.exitCode //
  empty
' 2>/dev/null)

INTERRUPTED=$(echo "$INPUT" | jq -r '.tool_response.interrupted // false')

# Skip success cases. If no exit_code field exists at all, only log when
# the tool_response explicitly says interrupted=true.
if [ -z "$EXIT_CODE" ] || [ "$EXIT_CODE" = "0" ] || [ "$EXIT_CODE" = "null" ]; then
    [ "$INTERRUPTED" != "true" ] && exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // .tool_response.output // empty' | head -c 500)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

LOGDIR="$HOME/.jjstack"
LOGFILE="$LOGDIR/command-failures.jsonl"
mkdir -p "$LOGDIR"

jq -n \
  --arg ts "$TS" \
  --arg cwd "$CWD" \
  --arg cmd "$CMD" \
  --arg exit_code "${EXIT_CODE:-unknown}" \
  --arg interrupted "$INTERRUPTED" \
  --arg err "$STDERR" \
  '{ts:$ts, cwd:$cwd, command:$cmd, exit_code:$exit_code, interrupted:($interrupted == "true"), stderr:$err}' \
  >> "$LOGFILE" 2>/dev/null || true

# Rotate: keep last 500 entries
LINES=$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)
if [ "$LINES" -gt 500 ]; then
    tail -500 "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null && mv "$LOGFILE.tmp" "$LOGFILE"
fi

exit 0
