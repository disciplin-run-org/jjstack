---
name: resume-from-clear
description: >
  Entry-side bootstrap for a session continuing another session's work
  after a clear or fresh restart — the paired inverse of /save-and-clear.
  Deterministic ladder: recover identity from $TM_WORKER_NAME, read your
  tubemail timeline, find your QM resume order, read the handover memory,
  read the ENTIRE previous session transcript (not just the tail), reload
  the key skills the resume order names, verify live state against reality,
  then continue the work — never end the first turn asking the user what
  to do. Trigger on: "resume from clear", "/resume-from-clear",
  "save-and-continue-session-from-a-clear-context", "continue the previous
  session", "pick up where the last session left off", a dispatched QM
  resume order that names this skill, or waking with a fresh context and
  evidence of unfinished work (handover memory, pending QM self-item,
  qa-build-loop decisions journal without a morning report).
  Do NOT trigger for: normal session starts with no predecessor work, or
  in-session task switching (no clear happened).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# resume-from-clear — Bootstrap a successor session losslessly

A cleared or fresh-restarted session is not a new hire — it is the same
worker mid-shift. This skill is the deterministic startup ladder that
turns an amnesiac fresh context back into that worker, without a human
having to say "read the previous transcript" (which Jesper had to type
manually for every resume before 2026-07-04).

Paired inverse of **/save-and-clear**: that skill writes the handover and
signals the fresh restart; this one consumes them. Factoring the
transition into two named skills makes it independently testable — the
test is literally `tm_restart(worker, fresh=true)` and watching this
skill execute (see Verification below).

## The ladder — run ALL steps, in order

### 1. Recover identity (deterministic, survives any clear)

```bash
echo "$TM_WORKER_NAME"
```

Set by the claude-tm wrapper before exec'ing claude; present even after
/clear and after fresh restarts. Empty output → this is not a tubemail
worker; stop here and tell the user this skill only applies to worker
sessions (the one legitimate early exit).

Do NOT infer your name from `$PWD` or the directory basename — role
suffixes and env overrides make that wrong (iris-qa hosts iris-qa-tm,
iris-qa-coder-tm, AND iris-qa-ui-tm in one cwd).

### 2. Read your timeline

If the manager already auto-typed `/sync-inbox` (fresh restarts do this
since tubemail mcp:2.10.5), its catch-up report is above you — use it.
Otherwise:

```
mcp__tubemail__tm_receive(worker="<name from step 1>", limit=20)
```

Never `tm_my_inbox` — it resolves identity hub-side and returns a
misleading "TM_WORKER_NAME not set" in the standard topology (fixed in
tubemail QM #555; the tool is deprecated for this use).

### 3. Find your resume order in QM

```
mcp__quartermaster__qm_queue_list(worker="<name>")
```

A pending or in_flight item addressed to you IS your work order — read
it fully (`qm_queue_read`). A /save-and-clear predecessor files one
labeled "Resume after save-and-clear"; a qa-build-loop predecessor's
names the loop state. Also check for `awaiting_review` items YOU filed
on other workers (`qm_queue_list` + `requested_by`) — closing those is
your duty too (verify evidence first; never close on the notice alone).

### 4. Read the handover memory

The resume order names it; otherwise check the project auto-memory
(`MEMORY.md` for `project_*handover*` pointers). The handover is the
predecessor's summary — useful, but it is NOT the authoritative source.

### 5. Read the ENTIRE previous session transcript — not just the tail

Per the global handover rule: a summary is the failure mode; the
transcript is the authoritative source.

```bash
ls -t ~/.claude/projects/<dashified-cwd>/*.jsonl | head -5
```

The predecessor is the newest large `.jsonl` that is not your own
session. Read it completely (delegate to an Explore agent if it is
huge — you need the conclusions in context, not every byte). Confirm the
handover against it; where they disagree, the transcript wins.

### 6. Reload the key skills

The resume order names them. qa-build-loop default set:
/product-manager-review, /kano-model, /dev-philosophy, /python-coder —
plus /qa-build-loop itself when resuming a loop.

### 7. Verify live state — never trust the summary alone

Memories and handovers are point-in-time; workers kept working while you
were down. Verify before acting:

- `git -C <repo> log --oneline -10` — what landed since the handover?
- `qm_queue_list` — did in-flight items move?
- Container health for anything the next action touches.

### 8. Continue

Execute the resume order's "continue from" actions. **Never end this
first turn asking the user what to do** — "listing options and waiting"
is the exact failure mode this skill exists to kill (2026-07-04: a fresh
session ended with "Just say the word" and the night was lost). If the
resume order is missing AND the timeline is empty AND no handover exists,
THEN you are genuinely a new session — say so and stop; that is not a
failure of this ladder.

## Verification (how to test this skill end-to-end)

1. Pick a worker mid-task; have it run /save-and-clear (files the QM
   resume order, signals fresh restart).
2. Watch: new claude process WITHOUT `--continue`, startup /rename,
   auto-typed /sync-inbox, QM dispatches the resume order.
3. Pass = the successor's first substantive turn continues the work and
   references the predecessor's state correctly. Fail = it asks the user
   anything.

Proven live 2026-07-04 on iris-qa-tm: the recovered session scanned 20
timeline events, read its pending QM items, verified evidence, and
closed its own review duty (#550) unaided.

## Relationship to other skills

| Skill | Side | Owns |
|---|---|---|
| **/save-and-clear** | exit | memory sweep, handover, QM resume order, fresh-restart signal |
| **/resume-from-clear** | entry | identity, timeline, resume order, transcript, verify, continue |
| **/qa-build-loop** | caller | Rule 3 invokes save-and-clear at ≥85% context; Rule 14 invokes this skill on amnesia |
| **tubemail /restart, /sync-inbox** | transport | the pty mechanics both sides ride on (tubemail owns these) |
