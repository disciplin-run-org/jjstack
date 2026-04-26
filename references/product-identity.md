# Product Identity — required preamble for jjstack design docs

Every design doc that comes out of `/office-hours` and every CEO review that
comes out of `/plan-ceo-review` MUST start with a `## Product Identity` block
filled in with concrete answers — not placeholders. This block is what
`leanspecs/mcp:3.2 docs_import` reads first to decide which capability is
Cap 1 (the central concern of the product) and how to slot the rest by
Kano level.

Without this block, the importer falls back to extraction-order numbering
and Cap 1 ends up being whatever the first shard happens to mention. That
silently misrepresents the product.

## Required sections

Drop this block at the very top of the design doc, immediately after the
title and front matter:

```markdown
## Product Identity

**Main Purpose** (one sentence — name the user, the job-to-be-done, the
distinctive thing the product does):
> <one sentence here, no qualifiers, no maybes>

**Cap 1 candidate** (the single capability that IS the product — if you had
to delete every other capability and keep one, this is it):
> <one capability name + one-clause justification>

**OKR shape** (this quarter's commitments):
- KR1 quantity: <how many thingies are we doing> — KPI: <metric>
- KR2 quality: <how good is the thingy> — KPI: <metric>
- KR3 efficiency: <how expensive is each thingy> — KPI: <metric>

**KPI candidates** (concrete metrics, not vibes):
- <metric 1>: <how it's measured> — <target this quarter>
- <metric 2>: <how it's measured> — <target this quarter>
- <metric 3>: <how it's measured> — <target this quarter>

**Kill criteria** (what would make us stop building this):
- <criterion 1>
- <criterion 2>

**Why now** (temporal interrogation — what changed that makes this the
right time to build this product):
> <one to three sentences>
```

## Critical-thinking prompts the skill should run before filling the block

Force the AI/user to actually think — don't accept the first answer.

1. **Main Purpose stress test**:
   - Does the sentence pass the "stranger reading the design doc would know
     what this product DOES" test? (Yes/No)
   - If no, rewrite. The bar is: a competent engineer not on the team can
     read this sentence and explain the product to a third party.
   - The sentence must NAME a user, a job-to-be-done, and a distinctive
     mechanism. "X is a tool that helps people do Y" fails — it has no
     mechanism. "X routes work between Claude Code sessions via tubemail
     so an orchestrator can drive long-running workers without alt-tabbing
     to terminals" passes.

2. **Cap 1 nomination challenge**:
   - List all proposed capabilities.
   - For each, ask: "If I deleted this capability tomorrow, would the
     product still be the same product?" Yes → not Cap 1. No → Cap 1
     candidate.
   - Often only ONE capability survives this challenge. That is Cap 1.
   - If multiple survive, the product is two products in a trench coat —
     flag it.

3. **OKR / KPI sanity**:
   - Each KR must reference a measurable KPI, not a vibe.
   - If KR2 (quality) reads as "high quality", reject and re-ask. The
     answer must be a number you can put on a dashboard.
   - KR3 (efficiency) must measure cost-per-unit, not total cost.

4. **Kill-criteria reality check**:
   - "We will stop building this if X" — X must be measurable AND
     decidable within one quarter. "If we don't get adoption" fails.
     "If MAU is below 10 by end of quarter Y" passes.

5. **Why now — temporal interrogation** (steal from `/office-hours` 0E):
   - What's true now that wasn't true 12 months ago?
   - What's the cost of waiting another 12 months?
   - Is this a wave we're catching, or a wave we're hoping for?

## How docs_import uses this block

`mcp:3.2 docs_import` runs Phase 0 (per-doc compression) followed by
Phase A (global synthesis):

- **A1** asks the LLM "what is the central purpose of this product?".
  When the corpus contains a `## Product Identity` block with a filled-in
  Main Purpose sentence, the LLM has the answer handed to it verbatim and
  the synthesis is reliable.
- **A2** asks the LLM to produce a ranked capability skeleton with Cap 1
  being the most-core. When the corpus names a Cap 1 candidate explicitly,
  the LLM uses it.
- **A3** assigns Kano levels. When the doc names KPIs and the OKR shape,
  Kano assignments are anchored in measurable outcomes rather than guesses.

A doc with the Identity block produces Cap 1 = the actual core thing.
A doc without it produces Cap 1 = whatever the first shard mentioned.

## When this block is NOT required

- Bug investigations (`/investigate` output)
- QA reports
- Retrospectives
- Single-feature briefs that explicitly amend an existing product

The block IS required for any doc that defines a product or proposes a
new top-level capability — i.e., the inputs to `docs_import` bootstrap
mode.
