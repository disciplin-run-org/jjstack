---
name: save-and-exit
version: 1.0.0
description: >
  Extract durable lessons from the current conversation into Hermes memory
  before the session ENDS. Same sweep as /save-and-clear — finds surprises,
  corrections, decisions, and operational facts worth keeping. Filters ephemera.
  Writes to memory tool, reports what was saved vs skipped, then ends with
  "all pertinent information saved - session complete" so the user can close.
  Use when: "save before exiting", "end of session save", "wrap up", "let's
  call it", "we're done", or when a session is ending and new decisions or
  corrections were made that future sessions should know about.
  For clearing to CONTINUE working in a fresh context, use /save-and-clear.
---

# save-and-exit — memory sweep, then end the session

The session is done. This skill sweeps the conversation for durable lessons,
writes them to Hermes memory, and closes cleanly.

For sessions that CONTINUE in a fresh context after clearing, use
/save-and-clear instead.

## When to invoke

- "save before exiting" / "save and exit"
- "wrap up the session"
- "end of session save"
- "we're done, save what matters"
- User types `exit` after substantial work — consider offering this proactively

Also invoke proactively when the user says "exit" or "we're done" AND the
session produced new decisions, corrections, or discoveries that would be
lost. Ask once: "Want me to sweep for anything worth saving first?"

## The sweep

### What to SAVE (durable, surprising, non-obvious)

| Type | Save when... |
|---|---|
| **feedback** | User corrected an approach ("don't do X — got burned by Y"). User confirmed a non-obvious choice. A cross-cutting principle the user stated this session. Always include **Why:** and **How to apply:** lines. |
| **memory** | Architecture decision not derivable from files. Operational ceiling discovered. Known recurring failure mode. Workaround pattern that generalizes. Tool quirk that will bite again. Environment fact (paths, services, credentials pattern). |
| **user** | New durable fact about the user's role, expertise, responsibilities, or how they want to collaborate. Promote only when seen 2-3 times — not on first mention. |

### What to SKIP (ephemera — already captured or stale)

- Code patterns, file paths — derivable by reading the project
- Git history, commit hashes — `git log` is authoritative
- Debugging fix recipes — fix is in the commit; save only if BUG CLASS generalizes
- Anything already in memory — check before adding
- Ephemeral task state — what was just done, current step in a loop
- Specific edits applied — captured in git/audit log
- Test counts, file sizes — re-derivable
- Task completion ("we finished X") — this is diary, not lesson

When in doubt, **skip and explain why** rather than dumping.

## Workflow

### Step 1: Check existing memory first

Read current memory (both user profile and personal notes) to know what's
already there. Do not duplicate existing entries.

### Step 2: Sweep the conversation

Re-read the session in your own context. For each candidate, ask:

1. Is it derivable from current files, git, or existing memory? → skip
2. Is it the user correcting an approach, or confirming a non-obvious choice? → feedback
3. Is it an operational fact or architectural decision not obvious from code? → memory
4. Is it a durable user identity/preference fact (seen 2-3+ times)? → user profile
5. Else → skip

Aim for **3-8 entries** from a typical end-of-session sweep. More than 10
usually means you're saving noise.

### Step 3: Dedup check

For each candidate, search existing memory for near-duplicates:
- If an existing entry already covers the same lesson, **update it** (replace)
  rather than creating a new entry.
- If the existing entry is now stale/wrong, **replace** it.
- Only create a new entry if nothing close exists.

### Step 4: Write to memory

Use the `memory` tool:
- `target='memory'` for operational facts, tool quirks, project conventions,
  architectural decisions, failure modes, environment facts
- `target='user'` for user profile facts (preferences, role, expertise)

For **feedback entries**, format the content as:
```
Rule: <the rule>
Why: <the incident or reason>
How to apply: <when this kicks in>
```

For **memory/operational entries**:
```
<the fact>
Why: <motivation or constraint>
How to apply: <how this should shape future behavior>
```

For time-sensitive facts, convert relative dates to absolute dates so the
memory survives time-shift.

Use `operations=[...]` batch form when writing multiple entries in one call
to stay within the character budget.

### Step 5: Triage pending skills (if any exist)

Before closing, check whether the pending skills queue has items:

```python
from pathlib import Path
import json
pending_dir = Path.home() / ".hermes/pending/skills"
items = list(pending_dir.glob("*.json")) if pending_dir.exists() else []
print(f"{len(items)} pending items")
```

If the queue is non-empty, run /pending-skills-triage now (inline — don't
defer). Apply the 3-tier cascade (Accept / Probation / Reject) and execute
programmatically so the queue is clean before the session ends. Unreviewed
items accumulate and rot — exit is the natural moment to drain them.

If the queue is empty, skip this step.

### Step 6: Report

Print a summary in this shape:

```
Memory saved (N entries):
  - <short description of what was saved>

Memory skipped:
  - <category> — <why>

Pending skills: <N accepted, M rejected, K on probation> (or "queue empty")
```

### Step 7: Close

End the reply with this exact line as the FINAL visible text — nothing after it:

```
all pertinent information saved - session complete
```

Do NOT add anything after the closing line. The user closes the terminal.

## Anti-patterns

- **Dumping the conversation into memory.** Memory is injected every turn —
  bloat degrades every future response. Curate, don't dump.
- **Saving "what we did" when "what we learned" is the durable part.**
  "We installed 10 skills" is history. "jjstack skills with gstack preambles
  need infra-dep stripping before install" is a lesson.
- **Creating new entries when an existing one should be updated.**
  Read memory first. Prefer extending over duplicating.
- **Saving without anchoring time-sensitive facts.**
  Use absolute dates, not "last week" or "recently".
- **Offering to save when nothing worth saving happened.**
  Short or purely mechanical sessions (a quick lookup, a one-liner fix)
  don't need a sweep. Use judgment.
- **Saving user preferences on first mention.** Wait for 2-3 occurrences.

## Relationship to other skills

| Skill | When to use |
|---|---|
| **/save-and-exit** | Session is ENDING for good — sweep then stop |
| **/save-and-clear** | Session CONTINUES after clearing — sweep then user types /clear |
| **/groom** | Memory has grown unwieldy — dedup and merge existing entries |
