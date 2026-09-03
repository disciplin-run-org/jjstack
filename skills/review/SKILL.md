---
name: review
version: 0.1.0
description: |
  Pre-landing review of staged or recent changes: deeper adversarial passes
  than gstack default, saves findings to {repo}/jjstack/, injects DNA. Use
  on the diff that is about to merge.
  Trigger on: "review my changes", "pre-landing review", "review the diff",
  "review before merge", "review this PR", "adversarial review", "deep review
  of changes".
  Do NOT trigger for: a specific PR by number (use /smart-review or the
  code-review plugin), security-focused review (use /security-review),
  two-stage spec-then-quality review (use /two-stage-review), processing
  incoming review feedback (use /receiving-code-review), or design/UI review
  (use /design-review).
  NOTE: this skill takes the name /review, which Claude Code v2.1.223+ also
  uses as a built-in alias of /code-review. Typing /review reaches this skill,
  not Claude's. For Claude Code's own reviewer - the one that takes a PR
  number, effort levels, --comment and --fix - type /code-review.
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

# jjstack review wrapper

This skill wraps gstack's `/review` with three enhancements:
1. Output redirected to `{repo}/jjstack/` (version-controlled, collaborative)
2. Deeper adversarial passes (configurable via `review.adversarial_passes`, default 2)
3. Quality loop iterates to 10/10

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

---

## Phase 1: Configure

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store: `MIN_SCORE`, `MAX_ITERATIONS`, `ADVERSARIAL_PASSES`, `OUTPUT_DIR`, DNA paths.

```bash
mkdir -p {OUTPUT_DIR}
```

Load DNA files if configured.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/review/SKILL.md
```

Follow ALL instructions with:
- Output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`
- After gstack's review, run `ADVERSARIAL_PASSES` additional adversarial review rounds (default 2, gstack default 1)

---

## Phase 3: Post-enhancement

### 3.1 Quality iteration loop

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol exactly, using the current document as the review target.

### 3.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol.

### 3.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
