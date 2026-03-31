---
name: design-review
version: 0.1.0
description: |
  Enhanced visual QA — saves findings to repo, iterates to 10/10, injects DNA.
  jjstack wrapper around gstack's design-review.
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

# jjstack design-review wrapper

Wraps gstack's `/design-review` with repo-local output, quality loop, and DNA injection.

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

Store: `MIN_SCORE`, `MAX_ITERATIONS`, `OUTPUT_DIR`, DNA paths. Create output dir. Load DNA.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/design-review/SKILL.md
```

Follow ALL instructions with output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`.

**jjstack responsive rule:** All designs MUST be responsive for desktop, tablet, and
mobile. Flag any desktop-only layouts as issues during the visual audit.

**jjstack font rule:** All fonts MUST be free, open-source, and available on
[Google Fonts](https://fonts.google.com/). Flag any commercial or proprietary fonts
found during the visual audit and suggest Google Fonts alternatives.

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
