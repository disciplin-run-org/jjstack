---
name: office-hours
version: 0.1.0
description: |
  Enhanced office hours — saves design docs to repo, iterates to 10/10, injects DNA.
  jjstack wrapper around gstack's office-hours.
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

# jjstack office-hours wrapper

This skill wraps gstack's `/office-hours` with three enhancements:
1. Output redirected to `{repo}/jjstack/` (version-controlled, collaborative)
2. Quality loop iterates to 10/10 (gstack stops at 8)
3. DNA injection for consistent voice/coding standards

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output contains `UPGRADE_AVAILABLE`: ask user to upgrade or snooze (see plan-ceo-review wrapper for full flow).

---

## Phase 1: Configure

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store config values: `MIN_SCORE`, `MAX_ITERATIONS`, `OUTPUT_LOCATION`, `OUTPUT_SUBDIR`, `DNA_VOICE`, `DNA_CODING`.

```bash
git rev-parse --show-toplevel 2>/dev/null || echo "NOT_A_REPO"
```

Set `OUTPUT_DIR` to `{repo_root}/{OUTPUT_SUBDIR}/` (or `~/.gstack/projects/$SLUG/` with warning if not in a repo).

```bash
mkdir -p {OUTPUT_DIR}
```

Load DNA files if configured. Apply voice/coding standards to all output.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/office-hours/SKILL.md
```

Follow ALL instructions in that file with these overrides:

- **Output path:** Write all artifacts to `{OUTPUT_DIR}` instead of `~/.gstack/projects/$SLUG/`.
- **Design doc reads:** Look in `{OUTPUT_DIR}` first, fall back to `~/.gstack/projects/$SLUG/`.
- **Let run as-is:** Preamble, session management, telemetry, AskUserQuestion format, Completeness Principle.

---

## Phase 3: Post-enhancement

### 3.1 Quality iteration loop

After gstack's review completes, check the quality score. If < `MIN_SCORE` (default 10) and iterations < `MAX_ITERATIONS` (default 3):

1. Dispatch a **fresh Agent subagent** for cold re-review (no prior scores, no iteration context).
2. Fix identified issues.
3. Re-dispatch for review.
4. If score >= MIN_SCORE: **DONE**.
5. If MAX_ITERATIONS reached: save as-is with `## Reviewer Concerns`, report honestly.

### 3.2 Output verification

```bash
ls {OUTPUT_DIR}/ 2>/dev/null || echo "NO_OUTPUT"
```

If output missing from `{OUTPUT_DIR}` but present in `~/.gstack/projects/$SLUG/`, move it and warn.

### 3.3 README maintenance

1. If no `README.md` at `{repo_root}`: create one.
2. If `README.md` exists: update if this session's changes affect it.
3. Do NOT add README to the jjstack output directory.
