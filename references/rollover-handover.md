# rollover-handover — the contract between /rollover and /resume-from-clear

One file, cited by both sides, so the thing written and the thing read
cannot drift apart. **/rollover** owns the write; **/resume-from-clear**
owns the read. No other skill touches either.

## The carriers, and why there is more than one

A session that hands work on is about to stop existing, so it cannot
retry. Every carrier below is enough on its own; they are redundant
because each has failed in the field.

| Carrier | Reaches | Fails when |
|---|---|---|
| **The handover slot** (`bin/jjstack-rollover-slot`) | any successor in the same directory | never — it is a file on disk |
| **The prompt hook** (`hooks/shared-memory.sh`) | a plain session, on its first prompt whatever the user types | the hook is not installed |
| **The QM resume order** | a worker, when QM dispatches it | the worker holds an in_flight item and dispatch is gated |
| **The tubemail self-message** | a worker, via the successor's auto-`/sync-inbox` | the manager predates the auto-catchup commit |

A plain session gets the slot, the hook, and the line /rollover ends on.
A worker gets those plus the resume order and the self-message.

## What /rollover writes into the slot

```bash
jjstack-rollover-slot write   # body on stdin; prints the path it wrote
```

The body is markdown and must carry exactly these fields. Anything else
is padding the successor has to read past.

```markdown
# Rollover handover — <worker name or "plain session"> — <UTC timestamp>

**Previous transcript:** <absolute path to the predecessor .jsonl>
**QM resume order:** #<id>   (workers only; "none" in a plain session)
**Reload these skills:** /<skill>, /<skill>, …

## Where the work stands
<three to six sentences: what was being done, what landed, what is
half-done and in which file or branch>

## Next actions
1. <the precise next thing, verifiable>
2. …

## Queued elsewhere — reference only, do NOT execute from here
- QM #<id> — <one line>; dispatches on its own after the resume order closes
```

Get the transcript path from the tool, never by guessing:

```bash
jjstack-rollover-slot transcript      # newest log in this project dir
```

At write time the newest log is the predecessor's own, which is what the
successor needs.

## Three rules the field taught, in the order they were learned

**1. Reference queued work, never inline it.** On 2026-07-04 a resume
order that copied a queued QA duty into its "next actions" made the
successor execute it under the resume order's authorization while the
real queue item sat pending. The work was double-tracked, results were
posted onto an item that was never dispatched, and the board showed a
state nobody could read. Inline next-actions are only for work that has
no queue item: verification steps, uncommitted follow-ups, board context.

**2. Never set `clear_first` on the resume order.** The fresh restart
already gives a clean context. With several carriers running, a delayed
`clear_first` dispatch wipes a successor another carrier already
bootstrapped — observed the same day, and the re-bootstrap cost more than
the rollover saved.

**3. The transcript is authoritative; this file is an index into it.**
The handover is a summary, and a summary is the failure mode. Where the
two disagree the transcript wins. That is why the slot names the
transcript path rather than trying to replace it.

## What /resume-from-clear does with it

Reads the slot, reads the ENTIRE transcript it names, verifies live state
against reality, continues the work — then retires the slot:

```bash
jjstack-rollover-slot consume         # renames it; prints what it retired
```

Consuming is what stops a second `/clear` from resuming the same work
twice. The file is renamed, never deleted, so a resume that goes wrong is
still readable afterwards.

## What must NEVER write here

`/save-and-clear` and `/save-and-exit` do not write a slot, do not file a
resume order, and do not post a self-message. That is the whole point of
the split: a clear starts a new task and an exit ends the session, so
neither may leave anything a successor could mistake for a handover.
`bin/jjstack-verify-skills` check 8 enforces it — the mechanisms above
are greppable, and a marker found in a skill that is not allowed to carry
it fails the build.
