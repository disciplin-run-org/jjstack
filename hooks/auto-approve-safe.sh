#!/bin/bash
# jjstack auto-approve hook — permission gate for Claude Code's PermissionRequest.
#
# Decision order, strictest first:
#   1. Read-only tools (Read, Glob, Grep, …)  → allow, no rating, no network
#   2. Non-Bash / empty command               → defer to the user
#   3. Deterministic denylist                 → defer, and it BEATS any rating.
#      This is the fail-closed core: the model never gets a vote on rm -rf $HOME,
#      a force-push, a hard reset, or curl-piped-to-shell.
#   4. Deterministic safe-readonly allowlist   → allow, no network
#   5. Everything else → Claude Haiku rates LOW / MEDIUM / HIGH, WITH CONTEXT
#      (cwd + the tool's own description + what counts as scratch space).
#      LOW → allow, MEDIUM/HIGH → defer, API failure → fail closed.
#
# Rating with context is the point. A context-free rater sees `rm -rf $SP/mut`
# and says MEDIUM, because it cannot know $SP is a session scratchpad. That one
# blind spot is what turns a code-review worker's mutation-testing run into a
# permission prompt every few seconds.
#
# ── tubemail / QM socket dispatch ────────────────────────────────────────────
# In a tubemail worker the forwarder holds something this script cannot know:
# the request_id of the permission_request it forwarded to the hub. Without
# telling it, a locally-approved tool leaves a pending entry stuck hub-side
# (RCA 2026-05-10, "stuck pending permissions").
#
# So on a LOCAL ALLOW we hand the decision to the forwarder's socket for
# pairing. Two rules make that safe:
#   • The local decision is authoritative. A forwarder still running the old
#     context-free policy may answer "defer"; we do not let that veto an allow
#     this script already reasoned about with context. Otherwise wiring the
#     socket would REGRESS every worker session.
#   • A local defer never touches the socket. There is nothing to pair — the
#     user's answer to the prompt resolves it through the normal channel.
# The payload carries `jjstack_decision` so a forwarder can honour it directly
# once tubemail supports that; harmless to forwarders that ignore it.
#
# Requires: jq, python3 (socket dispatch), curl (rating).
# API key: ANTHROPIC_API_KEY, or ~/.claude/anthropic_api_key (chmod 600).
#
# Test/diagnostic env vars (never grant approval on their own):
#   JJSTACK_HOOK_LOG=<path>        where to append the one-line audit trail
#   JJSTACK_HOOK_FORCE_RISK=LOW    skip the API, use this rating (test harness)
#   JJSTACK_HOOK_PRINT_PROMPT=1    print the rater prompt and defer, no API call

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
DESCRIPTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .tool_input.cwd // empty')

LOG_PATH="${JJSTACK_HOOK_LOG:-$HOME/.claude/logs/jjstack-permission-hook.log}"
log() {
  [ "$LOG_PATH" = "/dev/null" ] && return 0
  mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null || return 0
  printf '%s worker=%s tool=%s %s\n' \
    "$(date -Iseconds)" "${TM_WORKER_NAME:-${QM_WORKER_NAME:-<none>}}" \
    "${TOOL_NAME:-?}" "$1" >> "$LOG_PATH" 2>/dev/null
}

emit_allow() {
  jq -n '{hookSpecificOutput: {hookEventName: "PermissionRequest",
                               decision: {behavior: "allow"}}}'
  exit 0
}
# Exit 0 with no stdout = defer; the normal permission dialog appears.
defer() { log "decision=defer reason=${1:-policy}"; exit 0; }

# ── 1. read-only tools ───────────────────────────────────────────────────────
case "$TOOL_NAME" in
  Read|Glob|Grep|Search|WebSearch|WebFetch)
    log "decision=allow reason=read-only-tool"; emit_allow ;;
esac

# ── 2. non-Bash / empty ──────────────────────────────────────────────────────
[ "$TOOL_NAME" != "Bash" ] && defer "not-bash"
[ -z "$COMMAND" ] && defer "empty-command"

# ── 3. deterministic denylist — beats any rating ─────────────────────────────
# Anything here is refused no matter what the rater says. Kept narrow and
# literal on purpose: it must not swallow ordinary scratch-directory work.
DENY_RE='(^|[[:space:]=])(rm|rmdir|mv|cp|chmod|chown|shred|truncate)([[:space:]]+-[^[:space:]]+)*[[:space:]]+("?\$HOME|"?~/|/etc/|/usr/|/var/|/boot/|/bin/|/sbin/|/lib/|/opt/|/etc[[:space:]]|/$|/\*)'
GIT_DESTRUCTIVE_RE='git[[:space:]]+(push[[:space:]]+([^|;&]*[[:space:]])?(--force|-f)([[:space:]]|$)|reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f)'
PIPE_TO_SHELL_RE='(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'
OTHER_DANGER_RE='(^|[[:space:]])(dd[[:space:]]+[^|;&]*of=/dev/|mkfs|sudo[[:space:]]+rm|shutdown|reboot|:\(\)\{)'

if printf '%s' "$COMMAND" | grep -qE "$DENY_RE" \
   || printf '%s' "$COMMAND" | grep -qE "$GIT_DESTRUCTIVE_RE" \
   || printf '%s' "$COMMAND" | grep -qE "$PIPE_TO_SHELL_RE" \
   || printf '%s' "$COMMAND" | grep -qE "$OTHER_DANGER_RE"; then
  defer "denylist"
fi

# ── 4. deterministic safe-readonly allowlist ─────────────────────────────────
SAFE_READONLY='^\s*(ls|cat|head|tail|wc|file|stat|which|type|echo|printf|date|pwd|whoami|uname|id|env|printenv|git (status|log|diff|show|branch|tag|remote|rev-parse|describe))\b'

RISK=""
if printf '%s' "$COMMAND" | grep -qE "$SAFE_READONLY" \
   && ! printf '%s' "$COMMAND" | grep -qE '[;&|`]|\$\('; then
  RISK="LOW"
fi

# ── 5. rate the rest, with context ───────────────────────────────────────────
if [ -z "$RISK" ]; then
  RATER_SYSTEM="You are a shell command safety rater for a developer's own machine. Respond with exactly one word: LOW, MEDIUM, or HIGH.

Rate the risk of DAMAGE THE DEVELOPER WOULD MIND: destroying their real source files, their home directory, credentials, system packages, or published/remote state (force pushes, deploys, deletions on a remote).

Work confined to scratch space is routine and rates LOW even when it uses rm -rf, sed -i, chmod, cp -a or heredocs. Scratch space means: paths under /tmp, directories from mktemp, a session scratchpad such as /tmp/claude-*/…/scratchpad, throwaway git worktrees under .claude/worktrees, and fixture repos the command itself creates. Building, copying, mutating and deleting inside those is the normal shape of test and review work, not a hazard.

Rate on the effect, not on how alarming the verbs look."

  RATER_USER="Working directory: ${CWD:-unknown}
Stated purpose: ${DESCRIPTION:-none given}

Command:
$COMMAND"

  if [ -n "$JJSTACK_HOOK_PRINT_PROMPT" ]; then
    printf '%s\n\n%s\n' "$RATER_SYSTEM" "$RATER_USER"
    exit 0
  fi

  if [ -n "$JJSTACK_HOOK_FORCE_RISK" ]; then
    RISK="$JJSTACK_HOOK_FORCE_RISK"
  else
    API_KEY="${ANTHROPIC_API_KEY}"
    if [ -z "$API_KEY" ]; then
      KEY_FILE="$HOME/.claude/anthropic_api_key"
      if [ -f "$KEY_FILE" ]; then
        PERMS=$(stat -c '%a' "$KEY_FILE" 2>/dev/null || stat -f '%Lp' "$KEY_FILE" 2>/dev/null)
        case "$PERMS" in 600|400) ;; *) chmod 600 "$KEY_FILE" 2>/dev/null || true ;; esac
        API_KEY=$(tr -d '[:space:]' < "$KEY_FILE" 2>/dev/null)
      fi
    fi

    if [ -n "$API_KEY" ]; then
      PAYLOAD=$(jq -n --arg sys "$RATER_SYSTEM" --arg usr "$RATER_USER" \
        '{model: "claude-haiku-4-5-20251001", max_tokens: 10, system: $sys,
          messages: [{role: "user", content: $usr}]}')
      RESPONSE=$(curl -s --max-time 6 https://api.anthropic.com/v1/messages \
        -H "x-api-key: $API_KEY" -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" -d "$PAYLOAD" 2>/dev/null)
      RISK=$(printf '%s' "$RESPONSE" | jq -r '.content[0].text // ""' \
             | grep -oE 'LOW|MEDIUM|HIGH' | head -1)
    fi
  fi
fi

# Anything that is not an explicit LOW defers — including a missing key, a
# failed call, and an unparseable answer. Fail closed.
[ "$RISK" = "LOW" ] || defer "risk=${RISK:-unrated}"

# ── 6. local decision is ALLOW — pair it with the forwarder if there is one ──
LOCAL_DECISION="allow"

dispatch_socket() {  # $1 = socket path
  PAIR_PAYLOAD=$(printf '%s' "$INPUT" \
    | jq -c --arg d "$LOCAL_DECISION" '. + {jjstack_decision: $d}' 2>/dev/null)
  [ -z "$PAIR_PAYLOAD" ] && PAIR_PAYLOAD="$INPUT"
  # Script via -c so stdin stays free for the payload; a heredoc would hijack it.
  printf '%s' "$PAIR_PAYLOAD" | python3 -c '
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

for SOCK in "/tmp/tubemail-hook-${TM_WORKER_NAME}.sock" \
            "/tmp/qm-hook-${QM_WORKER_NAME}.sock"; do
  case "$SOCK" in *"-.sock") continue ;; esac
  [ -S "$SOCK" ] || continue
  RESP=$(dispatch_socket "$SOCK")
  if printf '%s' "$RESP" | grep -q '"behavior"[[:space:]]*:[[:space:]]*"allow"'; then
    log "decision=allow reason=risk-low paired=yes"
    printf '%s' "$RESP"
    exit 0
  fi
  # Forwarder deferred, timed out, or is running the old context-free policy.
  # Our decision stands; the hub sweeper reconciles any unpaired entry.
  log "decision=allow reason=risk-low paired=no socket=$SOCK"
  emit_allow
done

log "decision=allow reason=risk-low paired=n/a"
emit_allow
