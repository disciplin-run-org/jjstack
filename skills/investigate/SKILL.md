---
name: investigate
version: 0.1.0
description: |
  Enhanced debugging — saves root cause analysis to repo, injects DNA.
  jjstack wrapper around gstack's investigate.
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

# jjstack investigate wrapper

Wraps gstack's `/investigate` with repo-local output and DNA injection.
All debugging insights go into the heal framework (per jjstack philosophy).

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
cat ~/.claude/skills/gstack/investigate/SKILL.md
```

Follow ALL instructions with:
- Output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`
- All diagnostic checks must go into the heal framework (check.py or heal.py), never ad-hoc
- All fixes must go into the heal framework, never one-off commands

---

## Phase 3: Post-enhancement

### 3.1 Framework integration

If a `debug/heal.py` exists in the project, ensure all new diagnostic checks and fixes discovered during investigation are added to the appropriate `test_<component>.py` scripts.

If no heal framework exists, suggest running `/heal` to create one.

### 3.2 Output verification

Move any leaked files from `~/.gstack/projects/$SLUG/` to `{OUTPUT_DIR}`.

### 3.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
