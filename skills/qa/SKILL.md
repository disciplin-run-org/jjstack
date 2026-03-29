---
name: qa
version: 0.1.0
description: |
  Enhanced QA — saves reports to repo, applies jj-qa rules, iterates to 10/10.
  jjstack wrapper around gstack's qa.
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

# jjstack qa wrapper

This skill wraps gstack's `/qa` with enhancements:
1. Output redirected to `{repo}/jjstack/qa-reports/`
2. Quality loop iterates to 10/10 health score
3. jj-qa rules applied (cleanup, Docker-first, framework debugging)
4. DNA injection

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

Store: `MIN_SCORE`, `MAX_ITERATIONS`, `OUTPUT_DIR`, DNA paths.

```bash
mkdir -p {OUTPUT_DIR}/qa-reports
```

Load DNA files if configured.

**Load jj-qa rules:**

```bash
cat ~/.claude/skills/jjstack/skills/jj-qa/SKILL.md
```

Apply all jj-qa operational rules (cleanup, Docker-first, framework debugging, Kano depth) throughout this session.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/qa/SKILL.md
```

Follow ALL instructions with:
- Output path override: `~/.gstack/qa-reports/` → `{OUTPUT_DIR}/qa-reports/`
- QA cleanup: snapshot state before testing, reverse all test data after (per jj-qa Rule 1)
- Docker-first: always test against containers (per jj-qa Rule 2)

---

## Phase 3: Post-enhancement

### 3.1 Quality iteration loop

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol exactly, using the QA health score as the review target.

### 3.2 Cleanup verification

Verify all test data created during QA has been cleaned up. If any remains, clean it and warn.

### 3.3 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol. This is a QA skill — the protocol includes Step 3 for capturing `.gstack/qa-reports/` as well.

### 3.4 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
