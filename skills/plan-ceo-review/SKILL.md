---
name: plan-ceo-review
version: 0.1.0
description: |
  Enhanced CEO review — iterates to 10/10, saves to repo, injects DNA.
  jjstack wrapper around gstack's plan-ceo-review.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - WebSearch
  - Agent
  - Edit
  - Write
---

# jjstack plan-ceo-review wrapper

This skill wraps gstack's `/plan-ceo-review` with three enhancements:
1. Output redirected to `{repo}/jjstack/` (version-controlled, collaborative)
2. Quality loop iterates to 10/10 (gstack stops at 8)
3. DNA injection for consistent voice/coding standards

## Preamble

Run this first — check for jjstack updates:

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output contains `UPGRADE_AVAILABLE <old> <new>`:
- Ask the user with AskUserQuestion:
  - **A) "Yes, upgrade now"** → Run `git -C ~/.claude/skills/jjstack pull origin main` then `~/.claude/skills/jjstack/setup`. Continue with the skill after upgrade.
  - **B) "Always keep me up to date"** → Write `auto_upgrade true` to `~/.jjstack/config`, then upgrade as above.
  - **C) "Not now"** → Write snooze: read current level from `~/.jjstack/update-snoozed`, increment level (start at 1), write `<version> <level> <epoch>`. Continue with the skill.
  - **D) "Never ask again"** → Write `update_check false` to `~/.jjstack/config`. Continue.

If output contains `JUST_UPGRADED <old> <new>`:
- Tell the user: "Running jjstack v{new} (just updated from v{old})!"
- Read and show relevant section of `~/.claude/skills/jjstack/CHANGELOG.md` between old and new versions (if file exists).
- Continue with the skill.

---

## Phase 1: Configure

### 1.1 Read jjstack config

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

Then check for a project-level override:

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

If the project override exists, merge its keys on top of the global config. Keys not
present in the project config retain their global default value.

Store these values for use throughout the skill:
- `MIN_SCORE` from `review.min_score` (default: 10)
- `MAX_ITERATIONS` from `review.max_iterations` (default: 3)
- `OUTPUT_LOCATION` from `output.location` (default: "repo")
- `OUTPUT_SUBDIR` from `output.repo_subdir` (default: "jjstack")
- `DNA_VOICE` from `dna.voice` (default: null)
- `DNA_CODING` from `dna.coding` (default: null)

### 1.2 Detect output directory

```bash
git rev-parse --show-toplevel 2>/dev/null || echo "NOT_A_REPO"
```

- If in a git repo and `OUTPUT_LOCATION` is `repo`: set `OUTPUT_DIR` to `{repo_root}/{OUTPUT_SUBDIR}/`
- If not in a git repo OR `OUTPUT_LOCATION` is `home`: set `OUTPUT_DIR` to `~/.gstack/projects/$SLUG/` and warn: "Not in a git repo — writing output to ~/.gstack/projects/ instead."

Create the output directory:

```bash
mkdir -p {OUTPUT_DIR}/ceo-plans
```

### 1.3 Load DNA (if configured)

If `DNA_VOICE` is not null, read the file at that path. If `DNA_CODING` is not null,
read the file at that path.

**IMPORTANT:** Remember the DNA content. You MUST apply these standards to ALL artifacts
you produce during this session:
- Voice DNA → applies to writing style, tone, word choice in all documents
- Coding DNA → applies to any code examples, architecture decisions, technical writing

---

## Phase 2: Delegate to gstack

Now read and follow the gstack CEO review skill:

```bash
cat ~/.claude/skills/gstack/plan-ceo-review/SKILL.md
```

**Follow ALL instructions in that file** with these overrides:

### Output path substitution

Whenever the gstack skill instructs you to write files to `~/.gstack/projects/$SLUG/`,
write them to `{OUTPUT_DIR}` instead. Specifically:

- `~/.gstack/projects/$SLUG/ceo-plans/{filename}` → `{OUTPUT_DIR}/ceo-plans/{filename}`
- `~/.gstack/projects/$SLUG/ceo-plans/archive/` → `{OUTPUT_DIR}/ceo-plans/archive/`

### Design doc and handoff lookup

When the gstack skill reads design docs or handoff notes from `~/.gstack/projects/$SLUG/`:
1. **Look in `{OUTPUT_DIR}` FIRST** (jjstack output location)
2. If not found there, **fall back to `~/.gstack/projects/$SLUG/`** (gstack default location)

This dual-lookup ensures compatibility with design docs created before jjstack was installed.

### Let these run as-is (do NOT override)

- The gstack **preamble** (session management, telemetry, branch detection) — these write to `~/.gstack/` which is gstack's state directory, not project output.
- The gstack **analytics writes** (`~/.gstack/analytics/`) — these are gstack telemetry, not project artifacts.
- The gstack **AskUserQuestion format** — follow it exactly.
- The gstack **Completeness Principle** — follow it exactly.

---

## Phase 3: Post-enhancement

After the gstack skill completes, run these steps in order.

### 3.1 Quality iteration loop

The gstack skill has its own spec review loop (max 3 iterations, typically targeting 8/10).
After gstack's loop completes, check the final quality score.

If the score is **less than MIN_SCORE** (default: 10):

**Iteration loop** (up to MAX_ITERATIONS additional passes):

1. Use the `Agent` tool to dispatch a **fresh review subagent**. The subagent prompt
   MUST present the document as a **first-time review** — do NOT include:
   - The current iteration count
   - Prior quality scores
   - Change history or what was "fixed"
   - Any context that would anchor the reviewer's assessment

   The subagent reviews against these 5 dimensions (same as gstack):
   - **Completeness** — Requirements addressed? Edge cases?
   - **Consistency** — Parts agree? Contradictions?
   - **Clarity** — Can an engineer implement without questions?
   - **Scope** — Document creep? YAGNI violations?
   - **Feasibility** — Actually buildable? Hidden complexity?

2. Fix the issues identified by the subagent using the Edit tool.

3. Re-dispatch a new fresh subagent for review (step 1 again).

4. If score >= MIN_SCORE: **DONE**. Report final score.

5. If MAX_ITERATIONS reached and score still < MIN_SCORE:
   - Save the document as-is with a `## Reviewer Concerns` section listing unresolved issues
   - Report: "Reached max iterations ({N}). Final score: {X}/10. Remaining issues listed in Reviewer Concerns."
   - Do **NOT** inflate the score to exit the loop.

### 3.2 Output verification

Verify output landed in the right place:

```bash
ls {OUTPUT_DIR}/ceo-plans/ 2>/dev/null || echo "NO_OUTPUT"
```

If expected output files are missing from `{OUTPUT_DIR}` but present in
`~/.gstack/projects/$SLUG/ceo-plans/`, move them:

```bash
mv ~/.gstack/projects/$SLUG/ceo-plans/{filename} {OUTPUT_DIR}/ceo-plans/
```

And warn: "Output redirect missed — moved files from ~/.gstack/projects/ to {OUTPUT_DIR}. Please report this so the wrapper can be fixed."

### 3.3 README maintenance

Check the target project's README.md:

1. If no `README.md` exists at `{repo_root}/README.md`: create one that describes the
   project (name, purpose, setup, usage). Base it on what you learned during the CEO review.

2. If `README.md` exists: review whether the changes made in this session affect what
   the README describes. If the CEO review resulted in scope changes, new features, or
   architectural decisions that the README should reflect, update the relevant sections.

3. Do NOT add a README.md to the jjstack output directory — only to the project root.
