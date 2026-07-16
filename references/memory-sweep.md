# memory-sweep — the shared base for the save-and-* skills

The single most expensive failure mode after a session ends is
rediscovering a lesson the previous session already paid for. This
reference is the sweep that prevents it: it finds the durable lessons in
the current conversation and writes them to the project's auto-memory
before the context goes away.

It is the inverse of CLAUDE.md's "What NOT to save" rule: instead of a
list of things to skip when saving, this is the active sweep that applies
the rule and persists the rest.

**This file is the base, not a skill.** It is loaded by a calling skill
and owns everything up to and including the tubemail probe (steps 1-5a).
The *close* — what actually happens to the session — belongs to the
caller:

| Caller | Close it owns (5b / 5c) |
|---|---|
| **/save-and-clear** | Session CONTINUES in a fresh context: QM resume order + fresh restart via the manager, or "ready to clear". |
| **/save-and-exit** | Session ENDS for good: a clean `/exit` typed by the manager, or "ready to exit". No resume order, no process kill. |
| **/rollover** | Runs /save-and-clear with continuation mandatory, plus a pre-posted prompt injection. |

Do not invent a close here. Run steps 1-5a, then return to the calling
skill for 5b/5c.

## What to save vs what to skip

Apply the rules from CLAUDE.md's auto memory section. The hard part is
signal versus noise; default to skip when in doubt and explain why.

### Save (durable, surprising, non-obvious)

| Type | Save when… |
|---|---|
| **project** | Architecture decision not derivable from code (e.g. "tool X has two paths: live LLM and deterministic stub for tests"). Operational ceiling discovered (e.g. "local Qwen 64K can't sharpen 9+ child features"). Known bug worth flagging (e.g. "verb appears in two contradictory lists"). Workaround pattern that recurs (e.g. "docker exec smoke harness bypasses MCP timeout"). In-flight initiative state with date stamps for relative-date decay. |
| **feedback** | User correction ("don't do X — got burned by Y"). User confirmation of a non-obvious choice ("yes the bundled PR was right"). Cross-cutting principle the user enunciated this session ("prompt verb lists must mirror the gate's verb lists"). Always include **Why:** and **How to apply:** lines. |
| **user** | New durable fact about the user's role, expertise, responsibilities, or how they want to collaborate. Rarely fires on a single session — promote only when seen 2-3 times. |
| **reference** | Pointer to an external system the user named ("bugs go in Linear project FOO"). |

### Skip (ephemeral or already captured elsewhere)

- **Code patterns, file paths, architecture, conventions** — these can be
  derived by reading the current project. Saving them creates drift hazards.
- **Git history, commit hashes, who-changed-what** — `git log` / `git blame`
  are authoritative.
- **Debugging fix recipes** — the fix is in the code; commit message has the
  context. Save the *class of failure* if it generalizes; skip the recipe.
- **Anything already in CLAUDE.md, STATE.md, or product.json** — reading
  those is the canonical path. Don't duplicate.
- **Ephemeral task state** — in-progress work, current conversation context,
  what tool was just called. Use TaskCreate/TaskGet for that.
- **Specific edits applied** — if the audit log or git captures it, skip.
- **Test pass counts, file sizes, line counts** — re-derivable.

When the user explicitly asks to save something that falls into the skip
list, ask what was *surprising* or *non-obvious* about it — that's the
part worth keeping.

## Workflow

### 1. Locate the project memory directory

The auto-memory path is `~/.claude/projects/-<dashified-cwd>/memory/`. The
system prompt usually gives it directly under "auto memory". If not, derive
it from `pwd`:

```bash
pwd
# /home/jesper/PycharmProjects/ai-agents/leanspecs
# → ~/.claude/projects/-home-jesper-PycharmProjects-ai-agents-leanspecs/memory/
```

Read existing `MEMORY.md` first to avoid creating duplicate entries — prefer
updating an existing memory file over writing a new one with overlapping
content.

### 2. Sweep the conversation for candidates

Re-read the session in your own context. List candidate lessons. For each,
ask:

1. Is it derivable from current code, git, CLAUDE.md, or product.json? → skip.
2. Is it the user correcting an approach, OR confirming a non-obvious choice? → feedback.
3. Is it a fact about ongoing work (in-flight, decided, blocked, dated)? → project.
4. Is it a durable user identity / role / preference fact? → user.
5. Is it a pointer to an external system? → reference.
6. Else → skip.

Aim for 3-8 memory entries from a typical end-of-session sweep. More than 10
usually means you're saving noise.

### 2.5. Dedup check before writing (gbrain-assisted)

For each candidate memory, check whether a near-duplicate already exists
**before** creating a new file. This is the structural fix for memory
sprawl - the 477-file problem is what happens when every save creates a
fresh file even when an existing memory covers the same ground.

Two detection layers, tried in order. The first match wins; only fall
through if the prior layer returns nothing.

**Layer A - pattern_key grep (precise, no dependencies).**
If the candidate has an obvious `pattern_key` slug (e.g.
`docker-first-always`, `no-silent-catches`), grep the project memory
dir for any file with that key in its frontmatter:

```bash
grep -l "pattern_key:.*<slug>" ~/.claude/projects/<slug>/memory/*.md
```

If a file matches, that is the canonical memory. Proceed to **merge**
(below), not create.

**Layer B - gbrain similarity (recall, when available).**
If Layer A returned nothing and `gbrain` is on PATH, query gbrain for
the project's pages and check the top hit's similarity:

```bash
gbrain query "<candidate title or first 100 chars of body>" --json 2>/dev/null \
  | jq -r '.results[] | select(.tags[] == "project:<slug>") | "\(.score) \(.slug)"' \
  | head -1
```

If the top hit scores **>= 0.85**, treat it as a near-duplicate.
Resolve the gbrain slug back to a memory file path (the bridge writes
slugs as `<short-slug>/<title-kebab>`; the source file is recorded in
the corresponding `~/.gstack/projects/<slug>/learnings.jsonl` entry
under `source_file`). Proceed to **merge**.

If Layer B is unavailable (no `gbrain` binary, no PGLite at
`~/.gbrain/brain.pglite`, or the project has never been bridged), skip
this layer cleanly and proceed to create. **Do not block the sweep on
gbrain availability** - it must keep working in environments without
gbrain installed.

**PHI / sensitive projects never touch gbrain.** gbrain is one shared
local index across all projects; an unscoped query in another session
could surface these pages. For sensitive or standalone projects (e.g.
`mychart-sync`'s medical records), skip Layer B entirely and dedup with
Layer A only. Native per-project memory files are the whole store.

**Merge action.** When either layer returns a match:

1. Read the existing memory file.
2. Increment `recurrence_count` in the frontmatter (default 1 if absent,
   so first merge produces `recurrence_count: 2`).
3. Update `last_seen` to today's date (or add the field if absent).
4. If the new context adds information the existing body does not have,
   append it under a `## <Today's date> update` heading. If the new
   context is just another instance of the same lesson, do not append -
   the increment in `recurrence_count` is enough signal.
5. Report the merge in the step 5 summary as `🔁 Merged into existing`
   instead of `✅ Saved`.

**Promotion candidate flag.** After incrementing, if
`recurrence_count >= 3` AND the date span across observations covers
2+ sessions, append a one-line note to the file under `## Promotion
candidate` per `references/memory-promotion.md`. Do NOT auto-promote;
the user runs `/groom all` to act on flagged candidates.

### 3. Write each memory file (when dedup found no match)

One file per memory, named semantically by topic (not chronologically). Use
this frontmatter:

```markdown
---
name: <short title — used in the index>
description: <one specific line — used to decide relevance later>
type: project | feedback | user | reference
---

<body>
```

Body shape varies by type:

- **feedback**: lead with the rule, then `**Why:**` (the user's reason / past
  incident) and `**How to apply:**` (when this rule kicks in).
- **project**: lead with the fact, then `**Why:**` (motivation, often a
  constraint or stakeholder ask) and `**How to apply:**` (how this should
  shape your suggestions). Convert relative dates to absolute dates ("last
  Thursday" → "2026-04-23") so the memory survives time-shift.
- **user**: short paragraph(s); no Why/How required.
- **reference**: short pointer with system name and what it tracks.

### 4. Update MEMORY.md

Add one line per new file under the right section (Architecture, Feedback &
Preferences, User, References). Format: `- See \`<file.md>\` — <hook ≤ 150 chars>`.

`MEMORY.md` is auto-loaded into Claude's context every session, so brevity
matters. Lines after about 200 entries get truncated.

### 5. Report and verify

Print a summary in this exact shape:

```
✅ Saved (N new entries):
  - <file.md> — <one-line hook>

🔁 Merged into existing (M entries):
  - <file.md> — recurrence_count now <N>  [+ "promotion candidate" if N>=3 across 2+ sessions]

⏭️  Skipped intentionally:
  - <category> — <why> (e.g. "specific edits applied — captured in audit_log + git")

📁 Files modified on disk that survive the close (not memory but persistent):
  - <code/config/spec changes>
```

Then close the session via the calling skill's path, chosen by the
deterministic probe below.

### 5a. Detect tubemail (deterministic Bash probe)

Run this single Bash one-liner and read the output:

```bash
[ -n "$TM_WORKER_NAME" ] && echo "WORKER:$TM_WORKER_NAME" || echo "NO-WORKER"
```

- If output is `WORKER:<name>` → this session is a tubemail worker. Capture
  `<name>` literally (it is the authoritative worker name the `claude-tm`
  wrapper set; do NOT derive your own from `$PWD` or basename — the wrapper
  may apply role suffixes or env overrides). Proceed to the calling skill's
  **5b**.
- If output is `NO-WORKER` → proceed to the calling skill's **5c**.

`TM_WORKER_NAME` is set by `claude-tm` immediately before exec'ing claude
(see `tubemail/scripts/claude-tm` and `tubemail/channel/src/tubemail/__main__.py`).
It is not exported in any shell rc; its presence is the canonical "I was
launched as a worker" signal. The earlier rule about scanning the deferred
tool list for `mcp__tubemail-channel__*` was unreliable — the model does
not always introspect the deferred listing reliably during a skill run, so
detection silently fell through to the manual path. The Bash probe is
unambiguous.

**→ Return to the calling skill now for 5b/5c.**

## Why any close needs the tubemail manager

Slash commands and process control are owned by the Claude Code harness,
not the agent. Printing `/clear` or `/exit` in agent output renders as
inert text; there is no `claude clear` CLI binary, and hooks only run
shell commands. The single mechanism in this ecosystem that can clear,
exit, or relaunch a session on the agent's behalf is the **tubemail
manager process**, which owns the pty and is privileged for exactly this
purpose. That is why every 5b path routes through the manager, and why
every 5c path hands control back to the human — outside a tubemail
worker, no equivalent exists.

## Examples — what saving looked like in past sessions

**Good saves:**

- *project_spec_sharpen_live.md* — "spec_sharpen now calls live LLM via shared.llm.call_llm; deterministic stub kept as scaffold for tests."
  - Why save: the tool has two code paths now. Future-you reading mcp_sharpen.py will see both and need to know the live path is user-facing while the sync stub is for tests.

- *project_local_qwen_dense_feature_ceiling.md* — "Local Qwen 64K can't sharpen ~9+ child features (e.g. mcp:2.12); 180s ReadTimeout, falls back to deterministic scaffold."
  - Why save: operational fact, not in code or git. Saves future debug time when someone wonders why dense features return llm_used=false.

- *feedback_sharpen_triggers_must_mirror_gates.md* — "every gate-reject criterion must also be a prompt-side trigger to propose a rewrite."
  - Why save: a generalizable principle the user articulated after catching a specific bug. Applies beyond spec_sharpen to any LLM-call-with-gate pattern.

**Good skips:**

- "22 specific spec edits applied this session" — captured in audit_log + git.
- "49 unit tests pass" — re-runnable; trivially derivable.
- "/tmp/sharpen_*.json snapshots" — ephemeral; don't reference temp paths in memory.
- "mcp:2.18 → mcp:2.16 mapping after renumbering" — too narrow; if the user
  references "2.18" again, derive from current spec_list. Memory entries
  about ID-mapping fragments rot fast.

## Anti-patterns

- **Dumping the conversation into memory.** Memory is curation, not transcript.
  If you can't say in one sentence why a future session benefits from this
  entry, skip it.
- **Saving without dates on time-sensitive facts.** "Three PRs in flight"
  means nothing in three weeks. Always anchor to absolute dates.
- **Saving "what we did" when "what we learned" is the durable part.**
  "We applied 22 spec edits" is history. "Spec_sharpen has a verb-list drift
  failure mode" is a lesson. Save the lesson, not the diary entry.
- **Saving recipes for fixed bugs.** Once the fix is committed, the recipe is
  in the commit message. Save only if the bug class generalizes ("LLMs count
  words, not chars; server-side gate enforcement is the only reliable path").
- **Creating new files when an existing memory should be updated.** Read
  MEMORY.md first; prefer extending an existing entry over creating a near-
  duplicate. Examples of files that already exist in the leanspecs project:
  `feedback_be_the_sharpener.md`, `feedback_detail_is_natural_language.md`,
  `project_prompt_evolve_harness.md`. Always check before writing.

## Relationship to other persistence skills

| Skill | Output | Time horizon | Survives the close? |
|---|---|---|---|
| **/save-and-clear** | `~/.claude/projects/<...>/memory/*.md` | Cross-session, indefinite | Yes |
| **/save-and-exit** | `~/.claude/projects/<...>/memory/*.md` | Cross-session, indefinite | Yes |
| **/checkpoint** | One-time snapshot in conversation | Moment | No (the conversation goes) |
| **state-doc** | `STATE.md` in repo | Days to weeks, branch-scoped | Yes (in git) |
| **CLAUDE.md edit** | `CLAUDE.md` in repo | Permanent, all contributors | Yes (in git) |
| **TaskCreate** | In-conversation task list | Within session | No |

Pattern: when ending a non-trivial session,

1. Run the sweep (**/save-and-clear** or **/save-and-exit**) to extract
   cross-session lessons.
2. Update **STATE.md** if the work is mid-flight on a branch.
3. Promote any 3+ recurrence lesson from STATE.md to **CLAUDE.md** or memory
   per `references/memory-promotion.md` (see jjstack's state-doc skill).
4. Optionally **/checkpoint** if you want a resume-from-here snapshot.
5. Then let the calling skill's close run.
