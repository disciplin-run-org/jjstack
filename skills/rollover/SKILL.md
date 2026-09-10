---
name: rollover
description: >
  Continue THIS session's work in a fresh context — the only jjstack verb
  that hands work to a successor. Use it when context is filling up and
  stopping would lose the thread. Runs the shared memory sweep, writes a
  handover slot naming the previous transcript and the precise next
  actions, and (in a tubemail worker) files a QM resume order to itself,
  pre-posts a self-message, and signals a fresh restart; in a plain
  session it tells you to type /clear then /resume-from-clear. Its QM
  ledger is deliberately left open for the successor to inherit.
  Trigger on: "/rollover", "roll over the session", "session rollover",
  "roll into a fresh session", "restart with continuity", "clear and
  continue this work", "hand over to a fresh context", or a Quartermaster
  context-watchdog nudge.
  Do NOT trigger for: starting a DIFFERENT task with a clean context (use
  /save-and-clear — it resumes nothing), or ending the session for good
  (use /save-and-exit).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# rollover — same work, fresh context, no human relay

A session near its context ceiling has three bad options: keep burning
(quality degrades), stop (the thread is lost), or bare-`/clear` (identity
amnesia — the 2026-07-04 incident). /rollover is the fourth.

**This is the ONE verb that resumes work.** /save-and-clear and
/save-and-exit run the same memory sweep and then let the work go; only
this skill writes a handover, files a resume order, and points a
successor at the transcript. That separation is enforced by
`bin/jjstack-verify-skills` check 8, not just by prose — it exists
because /save-and-clear used to file a resume order for any session whose
work "continued", which is every mid-task session, so asking for a clean
context silently rolled the session over instead.

```
/rollover
  ├─ sweep:     references/memory-sweep.md   (steps 1-5a, shared)
  ├─ contract:  references/rollover-handover.md
  └─ entry:     /resume-from-clear           (runs in the successor)
```

## Steps 1-5a — run the shared sweep

```bash
cat ~/.claude/skills/jjstack/references/memory-sweep.md
```

Follow it exactly, then come back here. **Do not settle your QM ledger** —
`references/qm-ledger-settle.md` is for the two save-and-* closes. The
successor inherits your items on purpose.

## 5b. Read the handover contract

```bash
cat ~/.claude/skills/jjstack/references/rollover-handover.md
```

It defines the slot's fields, the transcript rule, and the two mistakes
that cost a night in the field (inlining queued work; `clear_first`).

## 5c. Write the handover slot — every session, worker or not

```bash
~/.claude/skills/jjstack/bin/jjstack-rollover-slot transcript
```

That is the predecessor transcript path: at this moment the newest log in
the project directory is your own. Compose the body per the contract,
then:

```bash
jjstack-rollover-slot write   # body on stdin; prints the path it wrote
```

The slot lives outside the auto-memory index, so no unrelated session
loads it and mistakes it for context. Capture the printed path.

## 5d. Plain session (no `$TM_WORKER_NAME`) — stop here

Step 5a's probe returned `NO-WORKER`. There is no manager to restart you
and no queue to file into. End the reply with this exact single line as
the FINAL visible text:

```
Handover written to <slot path> — type /clear, then /resume-from-clear.
```

The prompt hook is the second carrier: if you type something else first,
your next session is told the handover is waiting. Steps 5e-5g are worker
mechanics; skip them.

## 5e. Worker — check both carriers BEFORE staging

Both can be dead on arrival (the 2026-07-04 double failure):

1. **Manager version.** `tm_list_workers` shows your manager's
   `forwarder_version`. The auto-`/sync-inbox` carrier needs commit
   `788516b`+ (tubemail QM #553). Older than that, run
   `tm_update_manager(worker=<your name>)` first — it re-execs the
   manager and resumes you with `--continue`; then run /rollover again.
2. **QM dispatch gate.** If you currently hold an `in_flight` QM item,
   your resume order will be dispatch-blocked behind it. Note that inside
   the resume order itself ("read #<id> directly via `qm_queue_read` — it
   will not auto-dispatch") so the injection carrier compensates.

If BOTH are compromised, do not roll over blind — fix the manager first.

## 5f. Worker — file the resume order, then pre-post the injection

```
mcp__quartermaster__qm_queue_add(
    worker="<name>", priority="high",
    label="Rollover resume order",
    prompt="/resume-from-clear — you are the rolled-over continuation of
    the previous <name> session. Handover slot: <slot path>. Previous
    transcript: <transcript path>. Reload: <skills>. Continue from:
    <precise next actions>.")
```

Verify it exists with `qm_queue_read` and capture the id. **Never set
`clear_first`** (contract, rule 2). **Never inline queued work** into the
prompt (contract, rule 1).

Then mark the timeline settled — BEFORE the injection, never after:

```
mcp__tubemail__tm_session_boundary(worker="<name>", reason="/rollover")
```

**The order is the whole point.** `/sync-inbox fresh` treats everything
above the newest marker as settled and invisible. Post the marker first
and your predecessor's finished traffic is settled while the injection
below it still reaches the successor. Post it last and you have just
hidden the message that bootstraps the session you are handing to.

Now mail your successor, still before restarting:

```
mcp__tubemail__tm_send(worker="<TM_WORKER_NAME>",
    message="/resume-from-clear — you are the rolled-over continuation of
    this worker. Resume order QM #<id>. Handover slot: <slot path>.
    Previous transcript: <path>. Execute the full resume ladder; do not
    ask the user anything.")
```

The hub persists this on your own timeline while the process is down. The
fresh restart's manager auto-types `/sync-inbox fresh` once the successor
is ready, which surfaces it as prompt injection timed by readiness rather
than by a clock. The `fresh` argument is what makes the successor trust
the timeline over a memory it does not have.

## 5g. Worker — signal the fresh restart, to the MANAGER, exactly once

```
mcp__tubemail__tm_send(worker="<TM_WORKER_NAME>-manager",
    message="restart fresh",
    meta={"kind": "restart", "fresh": True})
```

Three rules, each violated live on 2026-07-04:

- **Target `<name>-manager`, not the bare worker name.** "restart fresh"
  is not a slash-command, so `tm_send` does not auto-route it; sent to
  the bare name it lands on your own timeline as mail and nothing
  restarts.
- **Send it ONCE.** Do not also call `tm_restart`, do not retry on a slow
  response. The fresh flag is one-shot: a duplicate kills the newborn
  fresh child, and the second restart reverts to `--continue` and resumes
  the stale conversation.
- **Never `tm_restart(worker=<self>)` from inside your own session.** It
  force-kills your process mid-tool-call and the dying transport can
  duplicate the signal (observed: two force_restarts 0.14s apart).
  `tm_restart` is for EXTERNAL recovery of hung workers.

Never a bare `/clear`. The manager restarts without `--continue`; the
startup `/rename` re-registers identity (QM #552); auto-`/sync-inbox
fresh` fires (QM #553) and reads the timeline identity-safely (QM #555),
from the boundary marker down (QM #615).

End the reply with this exact single line as the FINAL visible text:

```
Rolling over — handover at <slot path>, resume order QM #<id>, injection posted, fresh-restart signal sent.
```

## Verification

Testable end to end without a qa-build-loop:

1. On any mid-task session, invoke /rollover.
2. Observe: the slot exists (`jjstack-rollover-slot status` prints it);
   in a worker, QM shows the resume order and the hub timeline shows the
   boundary marker followed by the injection, in that order; the claude
   process relaunches with no `--continue`; `/rename` and `/sync-inbox
   fresh` fire.
3. Pass = the successor's first substantive turn continues the work and
   cites the predecessor's state, with no human input in between. Fail =
   the successor asks anything.

## Relationship to other skills

| Skill | Role |
|---|---|
| **/rollover** | the only verb that hands work on: sweep, handover, resume order, restart |
| **/resume-from-clear** | the entry side; consumes the handover in the successor |
| **/save-and-clear** | new task, clean context — sweeps, settles the ledger, resumes nothing |
| **/save-and-exit** | session over — sweeps, settles the ledger, exits |
| **/qa-build-loop** | calls this skill at ≥85% context (Rule 3) |
| **tubemail /restart, /sync-inbox** | the pty transport the worker path rides on |
