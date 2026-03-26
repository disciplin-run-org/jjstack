---
name: review
version: 0.1.0
description: |
  Enhanced pre-landing review — deeper adversarial passes, saves to repo, injects DNA.
  jjstack wrapper around gstack's review.
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

If score < `MIN_SCORE` and iterations < `MAX_ITERATIONS`: dispatch fresh Agent subagent for cold re-review, fix issues, re-review. Never inflate scores.

### 3.2 Output verification

Move any leaked files from `~/.gstack/projects/$SLUG/` to `{OUTPUT_DIR}`.

### 3.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
