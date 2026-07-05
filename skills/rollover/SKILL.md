---
name: rollover
description: >
  Roll a full (high-context) worker session over into a fresh successor
  that continues the same work — the one-verb tie between /save-and-clear
  (exit side) and /resume-from-clear (entry side). Runs the memory sweep +
  handover, files the QM resume order to itself, PRE-POSTS a tubemail
  self-message naming /resume-from-clear (the hub persists it while the
  worker is down; the fresh restart's auto-typed /sync-inbox delivers it
  as prompt injection at exactly the moment the successor is ready), then
  signals the fresh restart. Two independent carriers guarantee the
  successor bootstraps; either alone suffices.
  Trigger on: "/rollover", "roll over the session", "session rollover",
  "roll into a fresh session", "restart with continuity", "clear and
  continue", "hand over to a fresh context".
  Do NOT trigger for: ending a session with nothing to resume (use
  /save-and-clear alone), or a mid-conversation /clear the user will
  re-prompt themselves.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# rollover — Full session → fresh session, same work, zero human relay

A worker session near its context ceiling has three bad options: keep
burning (quality degrades), stop (the night is lost), or bare-/clear
(identity amnesia — the 2026-07-04 incident). /rollover is the fourth:
a lossless handover to a fresh context of the SAME worker, with the
successor guaranteed to pick the work up unaided.

This skill only ORCHESTRATES — the mechanics live in the two paired
skills it ties together, so each side stays independently testable:

```
/rollover
  ├─ exit side:   /save-and-clear   (memory sweep, handover, QM resume
  │                                  order, fresh-restart signal)
  ├─ injection:   pre-posted tubemail self-message  ← this skill's one
  │                                                    added step
  └─ entry side:  /resume-from-clear (runs in the successor)
```

## Preconditions

Worker session only: `echo "$TM_WORKER_NAME"` must print a name. In a
non-worker session, say so and fall back to /save-and-clear's manual
close (the human types /clear and re-prompts).

**Carrier health check** (do this BEFORE staging — the 2026-07-04
double-failure): both carriers can silently be dead on arrival:

1. **Manager version**: `tm_list_workers` shows your manager's
   `forwarder_version` (e.g. `1.0.4+<sha>`). The auto-`/sync-inbox`
   injection carrier needs commit `788516b`+ (tubemail QM #553). If your
   manager predates it, the injection will sit unread — run
   `tm_update_manager(worker=<your name>)` FIRST (it re-execs the
   manager and resumes you with --continue; then run /rollover again).
2. **QM dispatch gate**: if YOU currently hold an in_flight QM item,
   the resume order will be dispatch-blocked behind it (until
   quartermaster's restart-aware dispatch lands — QM #566). Note the
   blockage inside the resume order itself ("read #<id> directly via
   qm_queue_read — it will not auto-dispatch") so the injection carrier
   compensates, and verify carrier 1 is healthy before relying on it.

If BOTH carriers are compromised, do not roll over blind — fix the
manager first.

## Steps

### 1. Run /save-and-clear — WITH continuation mandatory

Execute the /save-and-clear skill in full. Rollover semantics tighten
its step 5b: the "if multi-turn work continues" branch is NOT optional
here — filing the QM resume order to yourself is mandatory, and its
prompt must begin with `/resume-from-clear` and name: the handover
memory path, the previous-transcript path (this session's), the key
skills to reload, and the precise next actions. Verify the item exists
(`qm_queue_read`) and capture its queue id `<QID>`.

**Never set `clear_first` on the resume order.** The fresh restart
already provides a clean context; with multiple carriers, a
`clear_first` dispatch can WIPE a successor that another carrier
already bootstrapped (observed 2026-07-04: the injection-bootstrapped
successor was mid-ladder when QM's delayed `clear_first` dispatch
cleared it again and forced a redundant re-bootstrap).

**Never duplicate queued QM items as inline duties in the resume
order.** The queue is the single source of truth for work assignment.
REFERENCE pending/in_flight items ("your queue holds #556 — it
dispatches after this resume order closes; also sweep for
awaiting_review items you filed"), never copy their content as "NEXT
ACTIONS: do #556's work". Observed 2026-07-04: a resume order that
inlined a queued QA duty made the successor execute it under the resume
order's authorization while the real item sat pending — double-tracked
work, results posted out-of-band onto a never-dispatched item, and a
queue state nobody could read at a glance. Inline next-actions are for
work that has NO queue item (uncommitted follow-ups, verification
steps, board context).

**Do not send the fresh-restart signal yet** — step 2 goes first.

### 2. Pre-post the prompt injection (the tie this skill adds)

Before restarting, mail your successor:

```
mcp__tubemail__tm_send(worker="<TM_WORKER_NAME>",
    message="/resume-from-clear — you are the rolled-over continuation
    of this worker. Your resume order is QM #<QID>. Handover:
    <memory path>. Previous transcript: <transcript path>. Execute the
    full resume ladder; do not ask the user anything.")
```

The hub persists this on your own timeline while the process restarts.
The fresh restart's manager auto-types `/sync-inbox` once the successor
is ready (tubemail mcp:2.10.5), which surfaces this message as an
unhandled inbound — prompt injection timed by readiness, not by a clock.
Belt and braces with the QM order: QM dispatch delivers #<QID> when the
worker registers idle. Either carrier alone bootstraps the successor.

### 3. Signal the fresh restart — to the MANAGER, exactly once

```
mcp__tubemail__tm_send(worker="<TM_WORKER_NAME>-manager",
    message="restart fresh",
    meta={"kind": "restart", "fresh": True})
```

Three hard-won rules (both violated live on 2026-07-04, run 1 and 2 of
the first field test):

- **Target `<name>-manager`, not the bare worker name.** "restart
  fresh" is not a slash-command, so tm_send does NOT auto-route it; sent
  to the bare name it lands on your own timeline as mail and no restart
  happens.
- **Send it ONCE.** Do not also call `tm_restart`, do not retry on a
  slow response. The fresh flag is one-shot: a duplicate signal kills
  the newborn fresh child and the second restart reverts to
  `--continue`, resuming the stale conversation.
- **Do NOT call `tm_restart(worker=<self>)` from inside your own
  session.** It force-kills your process mid-tool-call; the dying
  transport can duplicate the signal (observed: two force_restarts
  0.14s apart). tm_restart is for EXTERNAL recovery of hung workers;
  self-rollover uses the polite manager signal above (the manager types
  /exit when your prompt is ready — clean, single, buffered).

Never a bare /clear. The manager restarts WITHOUT `--continue`; the
startup `/rename` re-registers identity (QM #552); auto-`/sync-inbox`
fires (QM #553) and reads the timeline identity-safely (QM #555).

### 4. Close

End the reply with this exact single line as the FINAL visible text:

```
Rolling over — resume order QM #<QID> filed, injection posted, fresh-restart signal sent.
```

## What the successor does (for reference — owned by /resume-from-clear)

Identity from `$TM_WORKER_NAME` → timeline (`tm_receive`) → QM resume
order → handover memory → the ENTIRE previous transcript → reload key
skills → verify live state → continue. Never ends its first turn asking.

## Verification

The rollover transition is testable end-to-end without a qa-build-loop:

1. On any mid-task worker, invoke /rollover.
2. Observe: QM shows the resume order; the hub timeline shows the
   injection message; the claude process relaunches with no
   `--continue`; /rename + /sync-inbox fire; the successor's first
   substantive turn continues the work citing the predecessor's state.
3. Pass = no human input between invocation and resumed work.
   Fail = the successor asks anything.

## Relationship to other skills

| Skill | Role |
|---|---|
| **/rollover** | the one-verb transition: exit + injection + restart |
| **/save-and-clear** | exit mechanics (memory, handover, QM order, restart signal) |
| **/resume-from-clear** | entry mechanics (runs in the successor) |
| **/qa-build-loop** | calls /rollover at ≥85% context (Rule 3) |
| **tubemail /restart, /sync-inbox** | the pty transport both sides ride on |
