---
name: plan-design-review
version: 0.1.0
description: |
  Enhanced design plan review — iterates to 10/10, saves to repo, injects DNA.
  jjstack wrapper around gstack's plan-design-review.
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

# jjstack plan-design-review wrapper

Wraps gstack's `/plan-design-review` with repo-local output, quality loop, and DNA injection.

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
cat ~/.claude/skills/gstack/plan-design-review/SKILL.md
```

Follow ALL instructions with output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`.

**jjstack font rule (applies during and after gstack delegation):**

All fonts specified in the design MUST be free, open-source, and available on
[Google Fonts](https://fonts.google.com/). If the design plan names a commercial
or proprietary font, flag it as an issue and suggest the closest Google Fonts
alternative. This applies to:
- Primary/heading typefaces
- Body/reading typefaces
- Monospace/code typefaces
- Any font referenced in CSS, design tokens, or style guides

gstack is right that default stacks (Inter, Roboto, Arial, system) are lazy —
but the replacement must be free. Google Fonts has 1,700+ families including
distinctive options like Space Grotesk, Instrument Serif, Bricolage Grotesque,
Fraunces, and Playfair Display. There is no reason to use a commercial font.

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
