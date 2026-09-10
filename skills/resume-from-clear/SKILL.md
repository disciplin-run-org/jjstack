---
name: resume-from-clear
description: >
  Entry-side bootstrap for a session continuing a PREVIOUS session's work —
  the paired inverse of /rollover. Deterministic ladder: read the handover
  slot, recover identity, read your tubemail timeline and QM resume order
  (workers), read the ENTIRE previous transcript rather than its tail,
  reload the skills the handover names, verify live state against reality,
  continue the work, then retire the slot so a second clear cannot resume
  it twice. Never ends its first turn asking the user what to do.
  Trigger on exactly three carriers, and nothing vaguer: a live handover
  slot (`jjstack-rollover-slot status` succeeds, which the prompt hook
  surfaces for you), a dispatched QM resume order naming this skill, or a
  tubemail self-message naming it. Also on "/resume-from-clear", "resume
  from clear", "continue the previous session", "pick up where the last
  session left off".
  Do NOT trigger for: a normal session start, in-session task switching,
  or a hunch that work looks unfinished — a session cleared with
  /save-and-clear leaves no handover and must not be resumed.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# resume-from-clear — bootstrap a successor losslessly

A rolled-over session is not a new hire — it is the same work mid-flight.
This skill is the deterministic startup ladder that turns a fresh context
back into that worker, without a human having to say "read the previous
transcript".

Paired inverse of **/rollover**: that skill writes the handover and
signals the restart; this one consumes it.

## What may wake this skill — and what may not

Exactly three carriers, all of them artifacts you can point at:

| Carrier | How you see it |
|---|---|
| The handover slot | `jjstack-rollover-slot status` prints a path; the prompt hook says so on your first prompt |
| A QM resume order | a dispatched item whose prompt begins `/resume-from-clear` |
| A tubemail self-message | an inbound naming this skill on your own timeline |

**A hunch is not a carrier.** This skill used to trigger on "evidence of
unfinished work (handover memory, pending QM self-item, decisions journal
without a report)", which meant a session that merely swept its memory
could be resumed by the next one. /save-and-clear and /save-and-exit leave
no handover on purpose. No slot, no order, no message: you are a new
session, and saying so is correct, not a failure.

## The ladder — run ALL steps, in order

### 1. Read the handover slot

```bash
~/.claude/skills/jjstack/bin/jjstack-rollover-slot status
```

A path means a rollover is waiting; read that file. It names the previous
transcript, the resume order id (if any), the skills to reload, and the
next actions. Its contract is
`~/.claude/skills/jjstack/references/rollover-handover.md`.

Nothing printed and no QM order and no self-message → you are a new
session. Say so and stop. That is the one legitimate early exit.

### 2. Recover identity

```bash
echo "$TM_WORKER_NAME"
```

Set by the claude-tm wrapper before exec'ing claude; present even after a
clear or a fresh restart. Do NOT infer your name from `$PWD` or the
directory basename — role suffixes and env overrides make that wrong
(iris-qa hosts iris-qa-tm, iris-qa-coder-tm AND iris-qa-ui-tm in one cwd).

**Empty output is not an exit.** A plain session rolls over too: skip
steps 3, 4 and 9 (they are worker mechanics) and continue the ladder from
step 5 with the slot you just read.

### 3. Read your timeline (worker)

If the manager already auto-typed `/sync-inbox fresh`, its catch-up
report is above you — use it. Otherwise read your own timeline from the
last settled point:

```
mcp__tubemail__tm_receive(worker="<name from step 2>",
                          since_boundary=True, limit=20)
```

Never `tm_my_inbox` — it resolves identity hub-side and returns a
misleading "TM_WORKER_NAME not set" in the standard topology (tubemail QM
#555; the tool is deprecated for this use).

`since_boundary=True` starts the window strictly after the newest
`session_boundary` event. Everything at or above that marker belongs to a
session that has ended and is settled by definition — do not re-execute
it, and do not go looking above it. With no marker anywhere the read
degrades to the ordinary tail, and only the TRAILING inbounds are live:
an inbound with a later event of any other kind after it was already
being worked on by the session that is now gone.

### 4. Find your resume order in QM (worker)

```
mcp__quartermaster__qm_queue_list(worker="<name>")
```

A pending or in_flight item addressed to you IS your work order — read it
fully with `qm_queue_read`. A /rollover predecessor's is labeled
"Rollover resume order". Also check for `awaiting_review` items YOU filed
on other workers; closing those is your duty too, on evidence, never on
the notice alone.

### 5. Read the ENTIRE previous transcript — not just the tail

Per the global handover rule: a summary is the failure mode; the
transcript is authoritative. The slot names the path. Without a slot:

```bash
jjstack-rollover-slot transcript --exclude "<your own session id>"
```

Read it completely (delegate to an Explore agent if it is huge — you need
the conclusions in context, not every byte). If you must economize,
**extract the USER messages first, assistant text second**: the user's
corrections and instructions are the highest-value content and exactly
what a summary loses. First field run 2026-07-04: the successor read
assistant text only, and got away with it purely because the resume order
happened to carry the user's merge-gate instruction. Where the handover
and the transcript disagree, the transcript wins.

### 6. Reload the skills the handover names

qa-build-loop default set: /product-manager-review, /kano-model,
/dev-philosophy, /python-coder — plus /qa-build-loop itself when resuming
a loop.

### 7. Verify live state — never trust the summary alone

Handovers are point-in-time and other workers kept working while you were
down:

- `git -C <repo> log --oneline -10` — what landed since?
- `qm_queue_list` — did in-flight items move?
- container health for anything the next action touches.

### 8. Retire the handover

```bash
jjstack-rollover-slot consume
```

Do this once the ladder completes and before you start the work. An
unconsumed slot resumes the same work again on the next clear, and the
prompt hook keeps announcing it. The file is renamed, not deleted, so a
resume that goes wrong is still readable.

### 9. Close the resume order, then continue — via the queue (worker)

**Report and close your resume order promptly** (`qm_queue_report`, then
have it closed). Do NOT keep it open as an umbrella authorization for
other work. Queued work flows through QM dispatch AFTER the resume order
closes; executing a pending item's content "under" the resume order
double-tracks it and strands the real item (observed 2026-07-04: a QA duty
ran under the resume order while its own item sat pending, results posted
out-of-band, and the board showed a state nobody could read). Inline
next-actions cover only un-queued work: verification steps, uncommitted
follow-ups, board context.

**Never end this first turn asking the user what to do.** "Listing
options and waiting" is the exact failure this skill exists to kill
(2026-07-04: a fresh session ended with "Just say the word" and the night
was lost). The one exception is the genuinely-new-session case in step 1.

## Verification

1. Take a session mid-task and run /rollover.
2. Watch: the slot appears; in a worker, a new claude process without
   `--continue`, the startup `/rename`, the auto-typed `/sync-inbox`, and
   QM dispatching the resume order.
3. Pass = the successor's first substantive turn continues the work and
   cites the predecessor's state correctly, then the slot is consumed.
   Fail = it asks the user anything, or the slot is still live afterwards.

Proven live 2026-07-04 on iris-qa-tm: the recovered session scanned 20
timeline events, read its pending QM items, verified evidence, and closed
its own review duty (#550) unaided.

## Relationship to other skills

| Skill | Side | Owns |
|---|---|---|
| **/rollover** | exit | sweep, handover slot, QM resume order, fresh-restart signal |
| **/resume-from-clear** | entry | slot, identity, timeline, order, transcript, verify, consume, continue |
| **/save-and-clear** | exit | a NEW task after the clear — leaves nothing for this skill |
| **/save-and-exit** | exit | the end — leaves nothing for this skill |
| **/qa-build-loop** | caller | Rule 3 invokes /rollover at ≥85% context; Rule 14 invokes this skill on amnesia |
| **tubemail /restart, /sync-inbox** | transport | the pty mechanics both sides ride on |
