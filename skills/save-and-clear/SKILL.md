---
name: save-and-clear
description: >
  Extract durable lessons from the current conversation into project auto-memory
  before a /clear or /compact wipes them. Filters surprises and decisions worth
  keeping from ephemera worth dropping (code, git history, debugging recipes).
  Writes one memory file per durable lesson with proper frontmatter, updates
  MEMORY.md, reports what was saved versus deliberately skipped, then closes:
  if the session is a tubemail worker (detected by `$TM_WORKER_NAME` being
  set) the skill asks the worker's manager to type `/clear` into the pty
  via `mcp__tubemail__tm_send(worker="<TM_WORKER_NAME>", message="/clear")`
  — `tm_send` auto-routes harness commands to `<worker>-manager`, so the
  skill must pass the bare worker name, NOT the manager-suffixed form;
  otherwise it ends the reply with "all pertinent information saved -
  ready to clear" so the user types `/clear` themselves.
  Use whenever the user says "save before clear",
  "checkpoint memory", "save pertinent info", "prep for a clear", "what should
  we keep", or invokes /save-and-clear directly. Complements /checkpoint
  (snapshot of current git/work state) — save-and-clear targets cross-session
  memory, not within-session resume.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# save-and-clear — Pre-clear memory triage

The single most expensive failure mode after a `/clear` is rediscovering a
lesson the previous session already paid for. This skill catches that before
the conversation gets wiped, by sweeping the current session for durable
lessons and writing them to the project's auto-memory.

It is the inverse of CLAUDE.md's "What NOT to save" rule: instead of being a
list of things to skip when saving, this skill is the active sweep that
applies the rule and persists the rest.

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

## What to save vs what to skip

Apply the rules from CLAUDE.md's auto memory section. The hard part is signal
versus noise; default to skip when in doubt and explain why.

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

When the user explicitly asks to save something that falls into the skip list,
ask what was *surprising* or *non-obvious* about it — that's the part worth
keeping.

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

### 3. Write each memory file

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

### 5. Report and verify, then close

Print a summary in this exact shape:

```
✅ Saved (N entries):
  - <file.md> — <one-line hook>

⏭️  Skipped intentionally:
  - <category> — <why> (e.g. "specific edits applied — captured in audit_log + git")

📁 Files modified on disk that survive the clear (not memory but persistent):
  - <code/config/spec changes>
```

Then close the session via one of two paths, chosen by a deterministic
two-step probe.

#### 5a. Detect tubemail (deterministic Bash probe)

Run this single Bash one-liner and read the output:

```bash
[ -n "$TM_WORKER_NAME" ] && echo "WORKER:$TM_WORKER_NAME" || echo "NO-WORKER"
```

- If output is `WORKER:<name>` → this session is a tubemail worker. Capture
  `<name>` literally (it is the authoritative worker name the `claude-tm`
  wrapper set; do NOT derive your own from `$PWD` or basename — the wrapper
  may apply role suffixes or env overrides). Proceed to **5b**.
- If output is `NO-WORKER` → fall through to **5c**.

`TM_WORKER_NAME` is set by `claude-tm` immediately before exec'ing claude
(see `tubemail/scripts/claude-tm` and `tubemail/channel/src/tubemail/__main__.py`).
It is not exported in any shell rc; its presence is the canonical "I was
launched as a worker" signal. The earlier rule about scanning the deferred
tool list for `mcp__tubemail-channel__*` was unreliable — the model does
not always introspect the deferred listing reliably during a skill run, so
detection silently fell through to 5c. The Bash probe is unambiguous.

#### 5b. Tubemail-driven close

When 5a returned `WORKER:<name>`, ask the manager to type `/clear` into
this session's pty by making ONE call to `tm_send`:

```
mcp__tubemail__tm_send(worker="<name>", message="/clear")
```

**Pass the worker name straight from 5a — do NOT add a `-manager` suffix
yourself.** `tm_send` recognises `/clear` as a built-in harness command,
appends `-manager` for you, and routes a `kind: "type:/clear"` event so
the manager types `/clear` into this session's pty within ~1-2 seconds.
Adding the suffix yourself produces `<name>-manager-manager`, which is
the silent failure mode that has historically made this skill look
broken from inside a worker. Do not pass `meta`; `tm_send` overrides it
for harness commands anyway.

This is the legitimate, designed self-clear mechanism — the long-form
rationale at the bottom of this file explains why it works while every
other "agent typing /clear" path does not. Do not second-guess it; just
call the tool.

If `mcp__tubemail__tm_send` is not available (rare — means the session
lost its hub MCP connection between launch and now, e.g. the
tubemail-hub container is down): surface that fact verbatim and fall
through to **5c**.

End the assistant reply with this exact single line as the FINAL visible
text — nothing after it, no literal `/clear`:

```
All pertinent information saved — clear signal sent via tubemail manager.
```

A literal `/clear` line in the reply would race the manager's keystroke
and corrupt the new session's first prompt — the manager handles the
typing, the reply just announces completion.

#### 5c. Manual close (no tubemail, or 5b errored)

End the assistant reply with this exact single line as the FINAL visible
text — nothing after it:

```
all pertinent information saved - ready to clear
```

Do NOT add a literal `/clear` line. Outside a tubemail worker, the agent
cannot reach into its own pty; the user types `/clear` themselves. A
one-line confirmation BEFORE the closing line is fine (e.g. a last note
about a follow-up the user may want). Nothing after the closing line.

### Why 5b works while every other "agent self-clear" path does not

Slash commands like `/clear` are owned by the Claude Code harness, not the
agent. Printing `/clear` in agent output renders as inert text. There is
no `claude clear` CLI binary, and `Stop` / `UserPromptSubmit` hooks in
`settings.json` only run shell commands, not slash commands. The single
mechanism in this monorepo that can type a slash command into a session's
pty on the agent's behalf is the **tubemail manager process**, which
owns the pty and is privileged for exactly this purpose. 5b is therefore
the legitimate path — it's not a hack around a restriction, it's the
designed extension point. Outside a tubemail worker no equivalent exists,
which is why 5c hands control back to the human.

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

| Skill | Output | Time horizon | Survives /clear? |
|---|---|---|---|
| **save-and-clear** | `~/.claude/projects/<...>/memory/*.md` | Cross-session, indefinite | Yes |
| **/checkpoint** | One-time snapshot in conversation | Moment | No (the conversation goes) |
| **state-doc** | `STATE.md` in repo | Days to weeks, branch-scoped | Yes (in git) |
| **CLAUDE.md edit** | `CLAUDE.md` in repo | Permanent, all contributors | Yes (in git) |
| **TaskCreate** | In-conversation task list | Within session | No |

Pattern: when ending a non-trivial session,

1. Run **save-and-clear** to extract cross-session lessons.
2. Update **STATE.md** if the work is mid-flight on a branch.
3. Promote any 3+ recurrence lesson from STATE.md to **CLAUDE.md** or memory
   per `references/memory-promotion.md` (see jjstack's state-doc skill).
4. Optionally **/checkpoint** if you want a resume-from-here snapshot.
5. Then `/clear` cleanly.

## Iteration

This skill is meant to improve. After running it, if the user pushes back
("you saved too much" / "you missed X") capture the correction as a feedback
memory in the same project — then update the rules in this SKILL.md so the
next invocation does better. The skill is canonical at
`/home/jesper/PycharmProjects/jjstack/skills/save-and-clear/SKILL.md`.
