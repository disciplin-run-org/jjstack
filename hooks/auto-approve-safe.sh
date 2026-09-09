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
# Requires: jq, curl (python3 for the QM dispatch path below)
# API key: set ANTHROPIC_API_KEY env var, or store in ~/.claude/anthropic_api_key
#
# ── QM dispatch ─────────────────────────────────────────────────────────────
# When running inside a Quartermaster worker (claude-qm), the qm-tubemail
# forwarder runs its own risk policy AND knows the request_id of each
# permission_request it forwarded to the hub. Delegating to the forwarder
# lets it resolve the hub-side pending entry atomically with the approval,
# instead of leaving a stale pending behind. Non-QM sessions skip this block.
#
# We detect QM by QM_WORKER_NAME + the presence of the forwarder's unix
# socket. If anything fails (socket stale, forwarder wedged, timeout), we
# fall through to the normal logic below — the hook never blocks Claude.

INPUT=$(cat)

# Temporary diagnostic — logs every hook invocation, prune after bridge smoke-test is done.
echo "$(date -Iseconds) worker=${QM_WORKER_NAME:-<none>} tool=$(echo "$INPUT" | jq -r '.tool_name // "?"')" \
  >> /tmp/auto-approve-hook.log 2>/dev/null

if [ -n "$QM_WORKER_NAME" ]; then
  QM_HOOK_SOCK="/tmp/qm-hook-${QM_WORKER_NAME}.sock"
  if [ -S "$QM_HOOK_SOCK" ]; then
    # Short-circuit read-only tools locally even in QM mode — saves a round
    # trip for the common case and keeps the socket dedicated to Bash etc.
    case "$(echo "$INPUT" | jq -r '.tool_name // empty')" in
      Read|Glob|Grep|Search|WebSearch|WebFetch)
        jq -n '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "allow"}}}'
        exit 0
        ;;
    esac

    # Script passed via -c so stdin stays available for the hook JSON.
    # A heredoc here would hijack stdin and send empty bytes to the socket.
    QM_DISPATCH_PY='
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
'
    QM_RESPONSE=$(printf '%s' "$INPUT" | python3 -c "$QM_DISPATCH_PY" "$QM_HOOK_SOCK" 2>/dev/null)
    if [ -n "$QM_RESPONSE" ]; then
      # Forwarder responded — relay its JSON to Claude and exit.
      # An empty JSON object `{}` from the server means 'defer' (let the
      # normal prompt appear), which is a valid hook response.
      printf '%s' "$QM_RESPONSE"
      exit 0
    fi
    # Socket present but no response (timeout, crash) — fall through.
  fi
fi

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

# ── Heuristic decision, used whenever the Haiku tier is unavailable ───────────
#
# This used to be an allowlist of ~20 read-only command names that also deferred on
# ANY pipe or subshell, so `grep x src | head` prompted. In a normal dev session
# almost every command deferred, which is the opposite of what an auto-approve hook
# is for. Inverted: allow ordinary development work, defer the specific things that
# genuinely need a person.
#
# Safe to be generous here because this is NOT the only guard. block-destructive.sh
# runs as a separate PreToolUse hook on every Bash call and hard-blocks the
# catastrophic shapes (recursive deletes against home/root, find -delete, git clean,
# zero-truncation, disk writes) regardless of what this hook decides. Two independent
# layers; this one decides "ask the human?", that one decides "never, at all".
needs_human() {
  local c="$1"
  # privilege escalation
  grep -qEi '(^|[;&|[:space:]])(sudo|doas|su)([[:space:]]|$)'                <<<"$c" && return 0
  # rewriting or discarding history / work
  grep -qEi 'git[[:space:]]+push[^|;&]*(--force|-f[[:space:]]|--delete)'     <<<"$c" && return 0
  grep -qEi 'git[[:space:]]+push[^|;&]*[[:space:]](main|master|prod|production)\b' <<<"$c" && return 0
  grep -qEi 'git[[:space:]]+(reset[^|;&]*--hard|filter-repo|filter-branch)'  <<<"$c" && return 0
  # system-level package installs and services
  grep -qEi '(^|[;&|[:space:]])(pacman|apt|apt-get|dnf|yum|zypper|snap|flatpak)[[:space:]]+(-S|-R|install|remove|purge|upgrade)' <<<"$c" && return 0
  grep -qEi '(^|[;&|[:space:]])(systemctl|crontab|usermod|useradd|visudo)([[:space:]]|$)' <<<"$c" && return 0
  grep -qEi 'npm[[:space:]]+(i|install)[^|;&]*[[:space:]]-g\b'              <<<"$c" && return 0
  # piping the network into a shell
  grep -qEi '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|k)?sh'  <<<"$c" && return 0
  # reaching another machine
  grep -qEi '(^|[;&|[:space:]])(ssh|scp)([[:space:]]|$)'                    <<<"$c" && return 0
  grep -qEi 'rsync[^|;&]*[[:space:]][^[:space:]]+@[^[:space:]]+:'           <<<"$c" && return 0
  # destructive cloud / infra
  grep -qEi 'aws[[:space:]]+[a-z0-9-]+[[:space:]]+(delete|terminate|remove)' <<<"$c" && return 0
  grep -qEi 'kubectl[[:space:]]+delete|terraform[[:space:]]+(apply|destroy)' <<<"$c" && return 0
  grep -qEi 'docker[[:space:]]+system[[:space:]]+prune|gh[[:space:]]+repo[[:space:]]+delete' <<<"$c" && return 0
  # production secrets and config
  grep -qEi '\.env[.-]?(production|prod|beta)'                              <<<"$c" && return 0
  # broad permission changes
  grep -qEi 'chmod[^|;&]*[[:space:]]777|chown[^|;&]*-R[^|;&]*[[:space:]]/'  <<<"$c" && return 0
  return 1
}

heuristic_decide() {
  needs_human "$COMMAND" && defer
  allow
}

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
  heuristic_decide
fi

# ── Build JSON payload safely using jq ───────────────────────────────────────
PAYLOAD=$(jq -n \
  --arg cmd "$COMMAND" \
  '{
    model: "claude-haiku-4-5-20251001",
    max_tokens: 10,
    system: "You are a shell command safety rater for a developer machine. Respond with exactly one word: LOW, MEDIUM, or HIGH. Rate HIGH only if the command is irreversible or destructive: deletes or overwrites files (rm, truncate, dd), drops databases, force-pushes to remote branches, exfiltrates data, installs system packages, or modifies system configuration outside the project directory. Rate everything else LOW or MEDIUM. Prefer LOW.",
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
  LOW|MEDIUM)
    allow
    ;;
  HIGH)
    defer
    ;;
  *)
    # API call failed or unexpected response - fall back to the heuristic
    heuristic_decide
    ;;
esac
