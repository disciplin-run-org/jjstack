---
name: ship
version: 0.1.0
description: |
  Enhanced ship workflow — saves artifacts to repo, injects DNA.
  jjstack wrapper around gstack's ship.
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

# jjstack ship wrapper

This skill wraps gstack's `/ship` with two enhancements:
1. Output redirected to `{repo}/jjstack/` (version-controlled, collaborative)
2. DNA injection for consistent commit messages and PR descriptions

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

Store: `OUTPUT_DIR`, DNA paths.

```bash
mkdir -p {OUTPUT_DIR}
```

Load DNA files if configured.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/ship/SKILL.md
```

Follow ALL instructions with output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`.

---

## Phase 3: Post-enhancement

### 3.1 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol.

### 3.2 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
