#!/bin/bash
# jjstack auto-approve hook — permission gate for Claude Code's PermissionRequest.
#
# A destructive command may be approved when it is BOTH:
#   1. specific     — it names a definite target rather than sweeping a broad
#                     root, and
#   2. goal-aligned — it matches the stated purpose of the action.
# Deleting one build directory to rebuild it is ordinary work. Deleting a home
# directory is not, and neither is a force-push while the stated purpose is
# "fix a typo". Judging that is judgement, so it belongs to the rater.
#
# What is NOT left to judgement is the floor. Two deterministic rules bracket
# the rater so its opinion can never be the only thing standing between the
# user and an unrecoverable act:
#
#   FLOOR   unbounded reach or unreviewable content is refused outright, and
#           no rating can lift it. Nothing under here is "specific" by
#           definition: `rm -rf ~` names no target, and `curl … | sh` cannot
#           be specific about code nobody has seen.
#   PURPOSE alignment cannot be judged when nothing was stated. A destructive
#           command arriving with no description defers. This is what stops
#           criterion 2 being a rubber stamp.
#
# Decision order, strictest first:
#   1. Read-only tools            → allow, no rating, no network
#   2. Non-Bash / empty command   → defer
#   3. Absolute floor             → defer, beats any rating
#   4. Safe-readonly allowlist    → allow, no network
#   5. Destructive + no purpose   → defer
#   6. Everything else            → Haiku rates it WITH context and both
#                                   criteria. LOW → allow, else defer.
#                                   A missing key or failed call defers.
#
# Rating with context is the point. A context-free rater sees `rm -rf $SP/mut`
# and says MEDIUM, because it cannot know $SP is a session scratchpad — which
# turned a code-review worker's mutation run into a prompt every few seconds.
#
# NOTE ON GOAL CONTEXT: the "overall goal" is taken from the action's own
# stated purpose, NOT by reading transcript_path. Scraping the transcript would
# serve a broader notion of goal, but a session in a PHI project would leak
# medical content into the rater call, against the standing rule that sensitive
# data stays out of shared/third-party surfaces.
#
# ── tubemail / QM socket dispatch ────────────────────────────────────────────
# In a tubemail worker the forwarder holds the request_id of the
# permission_request it forwarded to the hub; without telling it, a locally
# approved tool leaves a pending entry stuck hub-side (RCA 2026-05-10).
# On a LOCAL ALLOW we hand the decision to that socket for pairing, under two
# rules: the local decision is authoritative (a forwarder still running the old
# context-free policy must not veto an allow reasoned about with context), and
# a local defer never touches the socket — the user's answer resolves it.
# The payload carries `jjstack_decision` so a forwarder can honour it directly.
#
# Requires: jq, python3 (socket dispatch), curl (rating).
# API key: ANTHROPIC_API_KEY, or ~/.claude/anthropic_api_key (chmod 600).
#
# Test/diagnostic env vars (none of them can grant an approval on their own):
#   JJSTACK_HOOK_LOG=<path>        where to append the one-line audit trail
#   JJSTACK_HOOK_CAPTURE=<path>    dump the raw payload (field discovery)
#   JJSTACK_HOOK_FORCE_RISK=LOW    skip the API, use this rating (test harness)
#   JJSTACK_HOOK_PRINT_PROMPT=1    print the rater prompt and defer, no API call

INPUT=$(cat)

[ -n "${JJSTACK_HOOK_CAPTURE:-}" ] && printf '%s' "$INPUT" > "$JJSTACK_HOOK_CAPTURE" 2>/dev/null

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

matches() { printf '%s' "$COMMAND" | grep -qE "$1"; }

# ── 3. absolute floor — no rating lifts these ────────────────────────────────
# A destructive verb whose target IS a root, with nothing after it. The
# trailing (space|end|;) is what separates `rm -rf $HOME` from the perfectly
# ordinary `rm -rf $HOME/project/build`.
ROOT_TARGET='("?\$\{?HOME\}?"?|~/?|/|/\*|\.)'
UNBOUNDED="(^|[[:space:];&|])(rm|rmdir|shred|chmod|chown)([[:space:]]+-[^[:space:]]+)*[[:space:]]+${ROOT_TARGET}([[:space:]]|;|$)"

# Piping fetched code into a shell: the content is unreviewable, so it can
# never satisfy the specificity criterion no matter what it claims to do.
PIPE_TO_SHELL='(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|k)?sh'

# Sending a local file to the network — the shape of credential exfiltration.
# Both the generic upload flags and, separately, any network command that so
# much as mentions a well-known secret path.
UPLOAD_FILE='(curl|wget)[^;&|]*(-d|--data|--data-binary|--data-raw|-T|--upload-file|-F|--form)[[:space:]=]*[^;&|]*@'
SECRET_PATH='(curl|wget|nc|ncat|scp|rsync|ftp)[^;&|]*(\.ssh/|\.aws/credentials|\.netrc|anthropic_api_key|id_rsa|id_ed25519|\.env([[:space:]]|$)|credentials\.json|\.git-credentials)'

DEVICE='(^|[[:space:]])(dd[[:space:]]+[^;&|]*of=/dev/|mkfs(\.[a-z0-9]+)?[[:space:]]|fdisk[[:space:]]|parted[[:space:]])'
FORKBOMB=':\(\)[[:space:]]*\{'
POWER='(^|[[:space:]])(shutdown|reboot|halt|poweroff)([[:space:]]|$)'
SUDO_ROOT='(^|[[:space:]])sudo[[:space:]]+(rm|dd|mkfs|shutdown|reboot)([[:space:]]|$)'

for rule in UNBOUNDED PIPE_TO_SHELL UPLOAD_FILE SECRET_PATH DEVICE FORKBOMB POWER SUDO_ROOT; do
  if matches "${!rule}"; then
    log "decision=defer reason=floor:$rule"
    exit 0
  fi
done

# ── 4. deterministic safe-readonly allowlist ─────────────────────────────────
SAFE_READONLY='^\s*(ls|cat|head|tail|wc|file|stat|which|type|echo|printf|date|pwd|whoami|uname|id|env|printenv|git (status|log|diff|show|branch|tag|remote|rev-parse|describe))\b'

RISK=""
if matches "$SAFE_READONLY" && ! matches '[;&|`]|\$\('; then
  RISK="LOW"
fi

# ── 5. destructive with no stated purpose → alignment is unjudgeable ─────────
DESTRUCTIVE="(^|[[:space:];&|])(rm|rmdir|mv|chmod|chown|shred|truncate|dd|kill|killall)([[:space:]]|$)|git[[:space:]]+(push[^;&|]*(--force|--force-with-lease|-f)([[:space:]]|$)|reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f)|(^|[[:space:]])sudo[[:space:]]|docker[[:space:]]+(rm|rmi|volume[[:space:]]+rm|system[[:space:]]+prune)|(DROP|TRUNCATE)[[:space:]]+(TABLE|DATABASE)"

if [ -z "$RISK" ] && [ -z "$DESCRIPTION" ] && matches "$DESTRUCTIVE"; then
  defer "destructive-without-stated-purpose"
fi

# ── 6. rate the rest, with context and both criteria ─────────────────────────
if [ -z "$RISK" ]; then
  RATER_SYSTEM="You are a permission gate for a developer working on their own machine. Respond with exactly one word: LOW, MEDIUM, or HIGH.

A destructive command is acceptable — LOW — when it is BOTH:
  1. SPECIFIC: it names a definite target. Removing one named directory, resetting one named branch, force-pushing one named feature branch. A command whose target is a whole home directory, a filesystem root, or an unbounded wildcard is NOT specific.
  2. ALIGNED with the stated purpose below. 'Remove the stale build directory' justifies deleting that build directory. It does not justify deleting a source tree, rewriting history, or touching credentials.

Rate MEDIUM or HIGH when the command reaches wider than its stated purpose needs, when the two do not match, or when the damage would be hard to undo and was not asked for.

Work confined to scratch space is routine and rates LOW even when it uses rm -rf, sed -i, chmod, cp -a or heredocs. Scratch space means paths under /tmp, directories from mktemp, a session scratchpad such as /tmp/claude-*/…/scratchpad, throwaway git worktrees under .claude/worktrees, and fixture repos the command itself creates. Building, mutating and deleting inside those is the normal shape of test and review work.

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

# Anything that is not an explicit LOW defers — missing key, failed call and
# unparseable answer included. Fail closed.
[ "$RISK" = "LOW" ] || defer "risk=${RISK:-unrated}"

# ── 7. local decision is ALLOW — pair it with the forwarder if there is one ──
LOCAL_DECISION="allow"

dispatch_socket() {
  PAIR_PAYLOAD=$(printf '%s' "$INPUT" \
    | jq -c --arg d "$LOCAL_DECISION" '. + {jjstack_decision: $d}' 2>/dev/null)
  [ -z "$PAIR_PAYLOAD" ] && PAIR_PAYLOAD="$INPUT"
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
  log "decision=allow reason=risk-low paired=no socket=$SOCK"
  emit_allow
done

log "decision=allow reason=risk-low paired=n/a"
emit_allow
