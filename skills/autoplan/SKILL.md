---
name: autoplan
version: 0.1.0
description: |
  Enhanced auto-review pipeline — saves all review artifacts to repo, iterates to 10/10.
  jjstack wrapper around gstack's autoplan.
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

# jjstack autoplan wrapper

Wraps gstack's `/autoplan` with repo-local output, quality loop, and DNA injection.
Autoplan runs CEO, design, and eng reviews sequentially — all enhanced by jjstack.

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
cat ~/.claude/skills/gstack/autoplan/SKILL.md
```

Follow ALL instructions with:
- Output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`
- Each sub-review (CEO, design, eng) inherits jjstack's quality thresholds
- Quality loop applies to each review stage independently

---

## Phase 3: Post-enhancement

### 3.1 Quality iteration loop

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol exactly. For autoplan, apply the loop to **each sub-review stage independently** (CEO, design, eng) — each gets its own iteration budget.

### 3.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol.

### 3.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
