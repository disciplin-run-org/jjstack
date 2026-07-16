---
name: save-and-clear
description: >
  Extract durable lessons from the current conversation into project auto-memory
  before a /clear or /compact wipes them. Filters surprises and decisions worth
  keeping from ephemera worth dropping (code, git history, debugging recipes).
  Writes one memory file per durable lesson with proper frontmatter, updates
  MEMORY.md, reports what was saved versus deliberately skipped, then closes:
  if the session is a tubemail worker (detected by `$TM_WORKER_NAME` being
  set) the skill files a QM resume order addressed to itself (when work
  continues) and signals a FRESH restart via the manager (restart without
  --continue: the startup /rename re-registers identity and the manager
  auto-types /sync-inbox) — never a bare /clear, which loses worker
  identity; the successor session bootstraps via /resume-from-clear.
  Otherwise it ends the reply with "all pertinent information saved -
  ready to clear" so the user types `/clear` themselves.
  Use whenever the user says "save before clear",
  "checkpoint memory", "save pertinent info", "prep for a clear", "what should
  we keep", or invokes /save-and-clear directly. Complements /checkpoint
  (snapshot of current git/work state) — save-and-clear targets cross-session
  memory, not within-session resume.
  For a session that is ENDING rather than continuing in a fresh context,
  use /save-and-exit — same sweep, terminal close.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# save-and-clear — memory sweep, then CONTINUE in a fresh context

The sweep is shared; the close is what makes this skill itself. This one
assumes **the work goes on** — the context gets wiped but the session (or
its successor) keeps going. For a session that is finishing for good, use
**/save-and-exit** instead.

## When to invoke

The user typically asks for this near the end of a long session. Common phrasings:

- "save pertinent information before a /clear"
- "checkpoint memory"
- "what should we keep before I clear"
- "prep for /clear"
- "/save-and-clear"

Invoke proactively if the user has expressed intent to clear/compact AND the
session has produced new architectural decisions, drift discoveries, operational
ceilings, prompt/code bugs, user preferences, or other lessons that future-you
would benefit from knowing without reading the whole transcript.

## Steps 1-5a — run the shared base

```bash
cat ~/.claude/skills/jjstack/references/memory-sweep.md
```

Follow it exactly: locate the memory dir, sweep for candidates, dedup,
write the files, update MEMORY.md, print the report, and run the 5a
tubemail probe. Then come back here for the close.

## 5b. Tubemail-driven close — QM resume order + FRESH restart

**Never signal a bare `/clear`.** Proven live 2026-07-04: a cleared
worker loses its own name, QM dispatch stops matching it, and the fresh
context sits idle asking "what would you like to do next". The designed
close is a **fresh restart** (tubemail QM #552/#553/#555): the manager
restarts claude WITHOUT `--continue`, the startup sequence types the
automatic `/rename` (identity re-registered), and the manager auto-types
`/sync-inbox` so the successor session catches up on its timeline.

When 5a returned `WORKER:<name>`:

1. **If multi-turn work continues past this session** (mid-loop, open QM
   items you filed, an unfinished work order): file the resume order
   FIRST, addressed to yourself:

   ```
   mcp__quartermaster__qm_queue_add(
       worker="<name>", priority="high",
       label="Resume after save-and-clear",
       prompt="/resume-from-clear — you are the continuation of the
       previous <name> session. Handover: <memory file path>. Previous
       transcript: <path>. Continue from: <precise next actions>.")
   ```

   Verify it exists (`qm_queue_read`) before proceeding. QM dispatches
   it once the fresh session registers as idle. If the session is truly
   DONE (nothing to resume), skip this step — and consider whether
   /save-and-exit was the right skill. **Never set `clear_first` on this
   item** — the fresh restart already yields a clean context, and a
   delayed `clear_first` dispatch can wipe a successor that another
   carrier already bootstrapped (observed live 2026-07-04).

2. **Signal the fresh restart** exactly as tubemail's `/restart` skill
   does in fresh mode — **to the MANAGER entity, exactly once**:

   ```
   mcp__tubemail__tm_send(worker="<name>-manager",
       message="restart fresh",
       meta={"kind": "restart", "fresh": True})
   ```

   Unlike the old typed-`/clear` path (where tm_send auto-routed the
   slash-command), "restart fresh" is NOT a slash-command — you must
   address `<name>-manager` yourself. Send it ONCE and never also call
   `tm_restart` on yourself: the fresh flag is one-shot, and a duplicate
   signal makes the second restart revert to `--continue` (observed
   live 2026-07-04).

If the tubemail tools are unavailable (hub down): surface that verbatim
and fall through to **5c**.

End the assistant reply with this exact single line as the FINAL visible
text — nothing after it:

```
All pertinent information saved — fresh-restart signal sent via tubemail manager.
```

The manager handles the exit and restart; the reply just announces
completion. The successor session's entry-side protocol is the
**/resume-from-clear** skill — the paired inverse of this one.

**Rollover variant:** when invoked via **/rollover** (the one-verb
transition), step 1's resume order is mandatory, and between steps 1
and 2 the skill PRE-POSTS a tubemail self-message naming
/resume-from-clear — the hub persists it during the restart and the
successor's auto-`/sync-inbox` delivers it as readiness-timed prompt
injection. See /rollover for the exact message shape.

## 5c. Manual close (no tubemail, or 5b errored)

End the assistant reply with this exact single line as the FINAL visible
text — nothing after it:

```
all pertinent information saved - ready to clear
```

Do NOT add a literal `/clear` line. Outside a tubemail worker, the agent
cannot reach into its own pty; the user types `/clear` themselves. A
one-line confirmation BEFORE the closing line is fine (e.g. a last note
about a follow-up the user may want). Nothing after the closing line.

## Why 5b beats a bare clear

The general rule — only the tubemail manager can act on a session's
process — is in the base under "Why any close needs the tubemail
manager". The clear-specific point: a fresh restart is strictly better
than the old typed-`/clear` path, because a bare clear keeps the process
but loses the conversation-held identity (the 2026-07-04 amnesia
incident), while a fresh restart rebuilds identity from the startup
sequence and auto-delivers the timeline.

## Iteration

This skill is meant to improve. After running it, if the user pushes back
("you saved too much" / "you missed X") capture the correction as a feedback
memory in the same project — then update the rules in the base or this
SKILL.md so the next invocation does better.

Canonical paths:
- close: `/home/jesper/PycharmProjects/jjstack/skills/save-and-clear/SKILL.md`
- sweep: `/home/jesper/PycharmProjects/jjstack/references/memory-sweep.md`
  (shared with /save-and-exit — a fix here fixes both)
