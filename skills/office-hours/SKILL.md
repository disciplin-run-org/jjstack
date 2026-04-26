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

## Phase 1.5: Product Identity preamble (REQUIRED)

Before delegating to gstack, capture the Product Identity block. This is
the input that `leanspecs/mcp:3.2 docs_import` reads first to decide which
capability is Cap 1 (the central concern of the product). Without it, the
importer falls back to extraction-order numbering and silently
misrepresents the product.

```bash
cat ~/.claude/skills/jjstack/references/product-identity.md
```

Run the critical-thinking prompts in that reference verbatim. Don't accept
the first answer — apply the stress test (Main Purpose), nomination
challenge (Cap 1), KPI sanity check (no vibes), kill-criteria reality
check, and why-now temporal interrogation. Iterate with the user until
each section passes.

**Output:** at the end of Phase 1.5, you have a fully-filled
`## Product Identity` markdown block held in memory. You will inject this
block at the top of the design doc gstack produces in Phase 2 (immediately
after the title/front matter, before the design body).

If the user is amending an existing product whose design doc already
carries an Identity block, read the existing block, present it for
confirmation, and only re-run the prompts for sections the user wants to
change.

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

After gstack's review completes, check the quality score.

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol exactly, using the current document as the review target.

### 3.1.5 Verify Product Identity block in output

After the quality loop converges, verify the design doc gstack wrote contains
the Product Identity block from Phase 1.5 at the very top (after title/front
matter, before any other heading).

If the block is missing or partial:
1. Inject the block from memory at the correct location.
2. Re-run the quality loop one more pass to make sure the body still aligns
   with the Identity block.

The Identity block is non-negotiable — design docs are the input to
`docs_import` and the importer needs the Main Purpose / Cap 1 candidate /
KPIs / kill criteria to reason correctly about the product.

### 3.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol to copy any files gstack wrote to `~/.gstack/projects/$SLUG/` into `{OUTPUT_DIR}`.

### 3.3 README maintenance

1. If no `README.md` at `{repo_root}`: create one.
2. If `README.md` exists: update if this session's changes affect it.
3. Do NOT add README to the jjstack output directory.
