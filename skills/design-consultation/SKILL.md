---
name: design-consultation
version: 0.1.0
description: |
  Enhanced design consultation — saves design system to repo, injects DNA.
  jjstack wrapper around gstack's design-consultation.
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

# jjstack design-consultation wrapper

Wraps gstack's `/design-consultation` with repo-local output and DNA injection.

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

Store: `OUTPUT_DIR`, DNA paths. Create output dir. Load DNA.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/design-consultation/SKILL.md
```

Follow ALL instructions with output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`.

---

## Phase 3: Post-enhancement

### 3.1 Output verification

Move any leaked files from `~/.gstack/projects/$SLUG/` to `{OUTPUT_DIR}`.

### 3.2 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
