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

**jjstack responsive rule:** All designs MUST be responsive for desktop, tablet, and
mobile. If gstack asks whether to design for desktop-only or responsive, always choose
responsive. Do not ask the user — this is not optional.

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

**jjstack design constraints (enforce during review):**

These are universal web design best practices. Flag violations as issues.

1. **Max 5 colors.** The entire site palette must not exceed 5 colors (primary,
   secondary, accent, background, text). Tints/shades of the same color are fine.
   More than 5 distinct colors creates visual noise.

2. **Max 5 fonts.** 2 primary fonts (headings + body) and up to 3 specialty fonts
   (action buttons, monospace/code, logo). If the design specifies more than 5
   fonts total, flag it — the site will feel incoherent.

3. **Consistent icon style.** All icons must come from the same family/style
   (e.g., all Lucide, all Phosphor, all Material). Mixing icon libraries (outlined
   + filled + hand-drawn) is a design crime.

4. **3 logo versions required.** Every project needs:
   - Horizontal (main) logo — for headers and wide spaces
   - Square logo — for social media, app icons, compact spaces
   - Simplified logo — for favicon, small sizes, monochrome contexts

5. **Logo must work on light AND dark backgrounds.** If only one version exists,
   flag it. The design should specify both variants or use a version with sufficient
   contrast on both.

6. **Favicon covers all platforms.** Not just one 16x16 icon — the design must
   account for browser tabs, mobile home screens, bookmarks, and social previews.
   A high-res source image (512x512+) is the minimum.

7. **Separation of design and content.** Colors, fonts, spacing, and component
   styles must be defined as design tokens or CSS variables — not hardcoded per page.
   Changing the design should not require editing content.

8. **Footer consistency.** The footer should be identical (or near-identical) across
   all pages. It contains: copyright, privacy/cookie links, social links, and
   secondary navigation. Flag designs where the footer varies between pages.

9. **NavBar consistency.** The navbar should be consistent across all pages with:
   - Active state indicator for current page
   - Scroll behavior (sticky/fixed)
   - Responsive collapse to hamburger menu on mobile
   Flag designs missing any of these.

10. **Specialty page types.** The front page may have a unique header/hero, but
    recurring page types (blog posts, articles, events, products) must have
    consistent templates with mandatory fields:
    - Blog/articles: author, publish date
    - Events: date, location, price/RSVP
    - Products: ID, price, image
    Flag designs that don't define templates for recurring content types.

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
