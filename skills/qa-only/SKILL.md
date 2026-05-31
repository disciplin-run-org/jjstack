---
name: qa-only
version: 0.1.0
description: |
  Browser QA execution, REPORT ONLY: run gstack /qa-only, save reports to
  {repo}/jjstack/, apply jj-qa operational rules. No auto-fix, no iteration -
  findings written down, then stop.
  Trigger on: "QA report only", "QA without fixes", "QA findings only",
  "report-only QA", "test and report only", "QA report", "test the site and
  report".
  Do NOT trigger for: QA with auto-fix (use /qa), TDD loop between iris-qa
  and a code worker (use /qa-loop), adversarial audit of the test suite
  (use /qa-review), or loading QA operational rules (use /jj-qa).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - WebSearch
  - Agent
---

# jjstack qa-only wrapper

This skill wraps gstack's `/qa-only` with enhancements:
1. Output redirected to `{repo}/jjstack/qa-reports/`
2. jj-qa rules applied (cleanup, Docker-first)
3. DNA injection

Note: qa-only does NOT fix issues — it only reports. No Write/Edit tools.

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

```bash
mkdir -p {OUTPUT_DIR}/qa-reports
```

Load DNA and jj-qa rules.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/qa-only/SKILL.md
```

Follow ALL instructions with output path override: `~/.gstack/qa-reports/` → `{OUTPUT_DIR}/qa-reports/`.

---

## Phase 3: Post-enhancement

### 3.1 Cleanup verification

Verify all test data created during QA has been cleaned up.

### 3.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol. This is a QA skill — the protocol includes Step 3 for capturing `.gstack/qa-reports/` as well.

### 3.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
