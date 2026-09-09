#!/bin/bash
# jjstack PermissionRequest hook — an audit trail and a tubemail relay.
#
# This file used to BE the permission policy: it asked Claude Haiku to rate
# every Bash command and, when the answer was anything but LOW, exited silently
# so the normal permission dialog appeared. The policy now lives in two places
# that cannot fail open or fail closed at 3am:
#
#   permissions in ~/.claude/settings.json  — mode and the prefix-expressible
#                                             deny rules (hooks/permissions.policy.json)
#   hooks/permission-floor.py               — a PreToolUse deny for the rules a
#                                             prefix cannot express
#
# so nothing here decides anything any more. What is left is worth keeping:
#
#   1. the audit line, which is how "how many times did a person get
#      interrupted, and why" is answerable at all (bin/jjstack-permission-audit
#      reads this log), and
#   2. the tubemail pairing, so the handful of requests that still reach a
#      human can be answered remotely with tm_respond_permission instead of
#      someone walking to that worker's terminal.
#
# Why it no longer rates. Between 2026-09-07 and 09 this hook deferred 183
# times; 147 of those were the rater returning nothing usable, because the
# answer parser accepts only a bare LOW/MEDIUM/HIGH and Haiku replies
# "LOW\n\n**Rationale:**..." on long commands, truncated at max_tokens: 10.
# Every one of the 183 was approved by the human it woke. An LLM in the hot
# path of a permission gate is a second failure mode protecting nothing.
#
# It cannot approve anything. There is no `allow` branch left, deliberately:
# an allow rule has no effect in bypassPermissions mode anyway, and a hook that
# can only observe cannot become a bypass. Reaching this hook now means the
# harness itself is asking — a critical-path rm, AskUserQuestion, a residual
# no mode auto-approves — and those are exactly the cases a person should see.
#
# Requires: jq. python3 only when a tubemail socket is present.
#
#   JJSTACK_HOOK_LOG=<path>   where to append the audit line (/dev/null to skip)

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
MODE=$(printf '%s' "$INPUT" | jq -r '.permission_mode // "?"')

LOG_PATH="${JJSTACK_HOOK_LOG:-$HOME/.claude/logs/jjstack-permission-hook.log}"
log() {
  [ "$LOG_PATH" = "/dev/null" ] && return 0
  mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null || return 0
  printf '%s worker=%s tool=%s mode=%s %s\n' \
    "$(date -Iseconds)" "${TM_WORKER_NAME:-<none>}" \
    "${TOOL_NAME:-?}" "$MODE" "$1" >> "$LOG_PATH" 2>/dev/null
}

# ── hand the request to the tubemail forwarder, if there is one ──────────────
# The forwarder holds the request_id of the permission_request it posted to the
# hub. Telling it about this request is what lets an orchestrator answer from
# tm_pending_permissions; without it the hub keeps a pending entry nobody can
# resolve (RCA 2026-05-10).
#
# Its reply is NOT relayed. Relaying the socket's bytes verbatim once let a
# stub add `updatedInput` and rewrite the command that was approved, and
# `[ -S ]` is the only check there is on the peer. We read the answer only to
# record whether the pairing happened.
dispatch_socket() {
  printf '%s' "$INPUT" | python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(2.0)
try:
    s.connect(sys.argv[1])
    s.sendall(sys.stdin.buffer.read())
    s.shutdown(socket.SHUT_WR)
    buf = bytearray()
    while True:
        chunk = s.recv(8192)
        if not chunk:
            break
        buf.extend(chunk)
    sys.stdout.buffer.write(bytes(buf))
except Exception:
    pass
finally:
    try:
        s.close()
    except Exception:
        pass
' "$1" 2>/dev/null
}

SOCK="/tmp/tubemail-hook-${TM_WORKER_NAME:-}.sock"
if [ -n "${TM_WORKER_NAME:-}" ] && [ -S "$SOCK" ]; then
  RESP=$(dispatch_socket "$SOCK")
  if [ -n "$RESP" ]; then
    log "decision=defer reason=residual paired=yes"
  else
    log "decision=defer reason=residual paired=no"
  fi
else
  log "decision=defer reason=residual paired=n/a"
fi

# Exit 0 with no stdout: the normal permission flow decides, as it would have
# without this hook installed.
exit 0
