#!/bin/bash
# capture-on-end.sh — SessionEnd hook. Auto-capture entry point.
#
# Robustness rule: this MUST be fast (sub-100ms) and MUST NOT block the session
# teardown. So it does the minimum — validate, enqueue a job, spawn the detached
# worker — and returns. All real work (LLM extraction, dedup, writes) happens in
# jjstack-capture-flush, launched with setsid+nohup so it outlives this hook.
#
# SessionEnd stdin payload: {session_id, transcript_path, cwd, reason, ...}.
# Always exits 0 (a failing capture must never disrupt the user's exit).
set -uo pipefail

# Never capture our own extractor's headless session (see jjstack-capture-flush).
[ -n "${JJSTACK_NO_CAPTURE:-}" ] && exit 0

PAYLOAD="$(cat 2>/dev/null || true)"
[ -z "$PAYLOAD" ] && exit 0

# One jq pass, tab-separated, to keep the hook fast (fewer process spawns).
IFS=$'\t' read -r SESSION_ID TRANSCRIPT CWD REASON < <(
    printf '%s' "$PAYLOAD" | jq -r '[.session_id // "", .transcript_path // "", .cwd // "", .reason // "other"] | @tsv' 2>/dev/null
)

# Need at least a session id and a readable transcript to do anything.
[ -n "$SESSION_ID" ] || exit 0
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
[ -n "$CWD" ] || CWD="$(pwd)"

QDIR="${JJSTACK_STATE_DIR:-$HOME/.jjstack}/capture-queue"
mkdir -p "$QDIR/done" "$QDIR/failed" 2>/dev/null || exit 0

# Idempotency: never re-enqueue a session already handled or in flight.
[ -e "$QDIR/done/$SESSION_ID.json" ] && exit 0
[ -e "$QDIR/failed/$SESSION_ID.json" ] && exit 0
[ -e "$QDIR/$SESSION_ID.inflight" ] && exit 0
[ -e "$QDIR/$SESSION_ID.json" ] && exit 0

# Enqueue the job (atomic: write temp then rename).
TMP="$QDIR/.$SESSION_ID.tmp.$$"
jq -nc \
    --arg tp "$TRANSCRIPT" --arg cwd "$CWD" --arg sid "$SESSION_ID" --arg reason "$REASON" \
    '{transcript_path:$tp, cwd:$cwd, session_id:$sid, reason:$reason, attempts:0}' \
    > "$TMP" 2>/dev/null || exit 0
mv "$TMP" "$QDIR/$SESSION_ID.json" 2>/dev/null || { rm -f "$TMP"; exit 0; }

# Detach the worker so teardown never waits.
FLUSH="$(cd "$(dirname "$0")/../bin" 2>/dev/null && pwd)/jjstack-capture-flush"
[ -x "$FLUSH" ] || FLUSH="$HOME/PycharmProjects/jjstack/bin/jjstack-capture-flush"
setsid nohup "$FLUSH" "$SESSION_ID" >/dev/null 2>&1 &

exit 0
