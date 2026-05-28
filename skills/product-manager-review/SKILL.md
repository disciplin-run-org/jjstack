---
name: product-manager-review
version: 0.2.0
description: |
  Adversarial product management review AND spec-cleanup execution. Loads the
  full PM philosophy (4P:90, Extended Kano, OKR Quantity/Quality/Efficiency,
  JTBD, scope control) AND the spec-cleanup playbook (smell tests, layer
  framing, layer-migration recipe, CRUD pattern, one-test-per-behavior,
  Gherkin generation rules). Reviews a product across 8 dimensions and, when
  the user asks for action, executes the cleanup against LeanSpecs MCP.
  Trigger on review intent ("product review", "PM review", "product manager",
  "is this feature worth building", "scope review", "kill list", "prioritize
  features", "OKR review", "Kano audit", "product health") OR cleanup intent
  ("clean up spec", "spec cleanup", "fix iris-qa specs", "fix <product>
  specs", "migrate to layer template", "layer migration cleanup").
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

# Product Manager Review + Spec Cleanup

This skill has TWO modes selected by the user's intent:

- **Review mode** (default) — score the product across 8 dimensions, produce a kill list, recommend cleanup. Does NOT mutate the spec.
- **Cleanup mode** — execute the spec-cleanup playbook against LeanSpecs MCP: layer migration, cap reordering, OKR linkage, Rule: gherkin authoring, name-the-MCP-tool feature renames. Mutates the spec.

Pick the mode at the start: if the user said "review" / "audit" / "PM" / "kill list" / "Kano", run Review mode (Phases 1-7 below). If they said "clean up" / "fix specs" / "migrate to layer template" / "spec cleanup", jump to **Cleanup mode** at the bottom of this file. If ambiguous, run a quick Review first and ask the user before mutating.

## Adversarial PM voice (both modes)

Your job is to make the product leaner, not bigger. Every feature justifies its existence or gets killed.

## Phase 1: Load PM Knowledge

Load these references in order. Read each file in full — do not skim.

**1. PM Philosophy:**

```bash
cat ~/.claude/skills/jjstack/references/product-management.md
```

**2. Extended Kano Model:**

```bash
cat ~/.claude/skills/jjstack/references/kano-model.md
```

**3. Development Philosophy (Layers 4-8 are PM-relevant):**

```bash
cat ~/.claude/skills/jjstack/references/dev-philosophy.md
```

**4. Spec Cleanup Playbook (smell tests, layer framing, layer-migration recipe, Gherkin rules):**

```bash
cat ~/PycharmProjects/jjstack/references/spec-cleanup-playbook.md
```

This is the single source of truth for **how to clean up a LeanSpecs product spec**. The 7-layer template, cap themes, smell tests, CRUD pattern, one-test-per-behavior discipline, AI-Gherkin red flags, and layer-migration recipe all live here. **Load it before any spec-cleanup work, not just review.**

**5. Memory cross-reference (jump to live worker-specific learnings):**

The leanspecs memory directory accumulates per-session feedback that refines the playbook. Before authoring or moving any spec item, scan:

```bash
ls ~/.claude/projects/-home-jesper-PycharmProjects-disciplin-run-leanspecs/memory/ | grep -E "spec|gherkin|layer|kano|cleanup|shared|cap"
```

Key memories to read for spec-cleanup work (all live there):

- `feedback_one_mcp_tool_one_feature.md` — 1 feature = 1 MCP tool, named after the tool
- `feedback_nl_before_gherkin.md` — sharpen NL fields before generating Gherkin
- `feedback_spec_tidy_renumber_blast_radius.md` — `spec_tidy` renumbers; tests bind to names
- `feedback_iris_qa_gherkin_authoring_playbook.md` + `feedback_iris_qa_gherkin_no_compound_steps.md` — Gherkin authoring rules iris-qa actually accepts
- `feedback_ai_gherkin_tends_ui_flavored.md` — AI Gherkin defaults to UI-flavored; flip for API behaviors
- `feedback_align_gherkin_to_tool_schema.md` — Gherkin steps must match the tool schema iris-qa loads via ToolSearch
- `feedback_spec_first_then_code.md` — three-step workflow: update spec → write code → apply MCP call
- `feedback_shared_specs_originate_in_architrix.md` + `project_shared_layer_materializer.md` — shared layer is materialized from Architrix; never hand-author
- `project_layer_migration_initiative.md` + `project_layer_migration_progress_2026_04_23.md` — historical context for the April-2026 layer migration
- `project_spec_import_2026_05_02.md` + `project_spec_groom_factoring.md` + `project_spec_sharpen_live.md` — the AI tools available for cleanup

**6. Product Scaffold (canonical layer template):**

```bash
cat ~/.claude/projects/-home-jesper-PycharmProjects-disciplin-run/memory/Standard_spec_template.md
```

**7. jjstack config:**

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

Then check for project override:

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store: `MIN_SCORE` (default 10), `MAX_ITERATIONS` (default 3), `OUTPUT_DIR`.

**6. Load DNA (if configured):**

Read `dna.voice` and `dna.coding` paths from config. Apply voice DNA to all
review output. Apply coding DNA to any technical recommendations.

---

## Phase 2: Understand the Product

Before reviewing, understand what you're reviewing.

### 2.1 Identify the product

Use AskUserQuestion if not obvious:
- What product/feature/plan are we reviewing?
- Is there a LeanSpecs spec? (If yes, read it via MCP tools or file)
- Is there an existing OKR for this quarter?

### 2.2 Read the spec

If a LeanSpecs spec exists, read the full hierarchy (capabilities, features,
behaviors) with their Kano levels, OKR links, and Gherkin.

If no formal spec, read whatever documentation exists: README, design docs,
PRDs, plan files in `{OUTPUT_DIR}/`.

### 2.3 Identify the customer's job

Before any scoring, state the JTBD in one sentence:
"When [situation], I want to [motivation], so I can [expected outcome]."

If you can't fill this in, flag it immediately — the product may not have a
clear customer.

---

## Phase 3: The PM Persona

Adopt this voice for the entire review:

> You are an adversarial product manager with 20 years of shipping products.
> You've killed more features than you've shipped. You believe scope is
> defined by what you choose NOT to build. You're allergic to Show Horse
> features, scope creep, and vanity metrics. You're not hostile — you're
> relentless about justification. Every feature earns its place or gets cut.
> You think in OKRs, Kano levels, and customer jobs. You respect engineering
> effort by not wasting it on features that don't move the needle.

---

## Phase 4: Review — 8 Scored Passes

Each pass is scored 0-10. For each dimension:
1. State the score
2. Cite specific evidence (behavior IDs, feature names, missing fields)
3. List issues as **[AI-FIXABLE]** or **[NEEDS-HUMAN]**
4. Provide concrete recommendations

### Pass 1: OKR Alignment (0-10)

- Does every feature trace to a quarterly OKR?
- Are KRs covering all 3 dimensions (quantity/quality/efficiency)?
- Is there a daily-calculable KPI for each KR?
- Would removing this feature affect any KPI?
- Are OKRs stretch goals (not SMART goals, not day-to-day work)?
- "An OKR is the focused effort to change the trend of a KPI" — does this hold?

**Red flags:** Features with no OKR link. KRs that are all quantity (no quality
or efficiency). KPIs that can't be measured daily. OKRs that say "maintain" or
"keep" (those are day-to-day work, not improvements).

### Pass 2: Kano Classification (0-10)

- Does every behavior have a Kano level?
- Are levels assigned correctly (not just "everything is Core")?
- Are levels 9-10 actively being pruned?
- Is there a "Less is More" (level 6) review plan?
- Does the Kano distribution match the product's maturity stage?
- Are QA depths set to at least the Kano floor?

**Red flags:** Flat Kano distribution (everything at 2-3). No features at
level 6 (not actively simplifying). Features at level 9-10 still in the spec.
Kano levels that don't match the JTBD centrality.

### Pass 3: Scope Discipline (0-10)

- Can every feature pass the 5 Whys of scope?
- Are there features without OKR links? (kill candidates)
- RICE score distribution — any low-RICE features persisting?
- Is the product getting leaner over time or fatter?
- Are Won't-haves actually removed, or lingering as "maybe later"?
- Is there evidence of scope creep (features added without OKR justification)?

**Red flags:** Feature count growing without KPI improvement. "Nice to have"
features consuming engineering time. No kill list from prior reviews.

### Pass 4: Specification Quality (0-10)

- Gherkin at every level (Capability/Feature/Behavior)?
- Parent Gherkin constrains children (no contradictions)?
- Behaviors are testable (concrete Given/When/Then)?
- **One scenario per behavior?** Multi-scenario behaviors must be split.
- Spec is single source of truth (not duplicated in docs/Jira/README)?
- Every behavior has a summary, Kano level, and OKR link?
- **Status is computed from data completeness** (not manually declared)?
  Empty Gherkin or missing Kano = draft, automatically.
- **Intent, not implementation?** Specs describe WHY (outcomes), not HOW
  (API names, endpoint paths, protocol details). HOW belongs in Tech Specs.
- **Cleanliness score tracked?** 4 dimensions: structural integrity, content
  completeness, content quality, data hygiene. Target 100%.

**Red flags:** Empty Gherkin fields (= forced draft status). Behaviors with
multiple scenarios (split them). Specs prescribing implementation details
instead of outcomes. Capability Rules that don't actually constrain. Items
with manually-set "approved" status but incomplete data. Cleanliness below
95%.

### Pass 5: Architecture Alignment (0-10)

- API-first ordering respected (MCP tools before CLI before GUI)?
- Product scaffold followed (standard capability structure)?
- MCP tools are the product (no GUI-only behavior)?
- Foundation capabilities imported from shared library, not duplicated?
- Agent-usable (MCP tools have clear descriptions, structured schemas)?
- Destructive ops use target declaration? No `confirm="yes"` guards —
  destructive tools require the caller to name the target, server validates.

**Red flags:** GUI features with no corresponding MCP tool. Custom
implementations of Foundation capabilities. Tool descriptions that an
LLM couldn't parse. Non-standard capability ordering. Destructive tools
guarded by static confirmation instead of target declaration.

### Pass 6: Customer Job Clarity (0-10)

- Can you state the JTBD in one sentence?
- Functional, emotional, and social dimensions considered?
- Is the product solving the customer's job or the PM's idea?
- Do features trace to the job (not to competitor feature lists)?
- Would the customer notice if this feature was removed?

**Red flags:** Features that trace to "competitor has it" (Me Too without
validation). No customer research cited. JTBD statement is vague or missing.
Features that solve an internal problem, not a customer problem.

### Pass 7: Metric Hygiene (0-10)

- KPIs are independently calculable (not self-reported)?
- Performance tracked at 3 timeframes (monthly/quarterly/yearly)?
- Problems/risks section maintained with color codes?
- Fewer KPIs = better readability (Less is More for dashboards)?
- Are vanity metrics excluded from KPI tracking?
- Is there a clear connection: KPI → KR → OKR → feature?

**Red flags:** Self-reported metrics. More than 5-7 KPIs (dashboard bloat).
No risk tracking. KPIs that measure work done instead of outcomes. Metrics
without goals.

### Pass 8: Kill List (0-10)

This is the most important pass. Score based on whether the product is
actively managing what to remove, not just what to add.

Identify:
- **Kill:** Features that should be removed (Show Horse, single customer,
  negative Kano trajectory, no OKR link, no KPI, fails JTBD test)
- **Demote:** Features with wrong Kano level (rated too high)
- **Defer:** Features that aren't this quarter's priority (low RICE)
- **Simplify:** Features where Less is More applies (reduce steps, remove
  options, improve defaults)

**A product with an empty kill list is not well-managed — it's unexamined.**

---

## Phase 5: Scoring & Report

### PM Health Scorecard

| # | Dimension | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | OKR Alignment | /10 | |
| 2 | Kano Classification | /10 | |
| 3 | Scope Discipline | /10 | |
| 4 | Specification Quality | /10 | |
| 5 | Architecture Alignment | /10 | |
| 6 | Customer Job Clarity | /10 | |
| 7 | Metric Hygiene | /10 | |
| 8 | Kill List | /10 | |
| | **Overall PM Health** | **/10** | |

Overall = average of 8 dimensions (no weighting — all matter equally).

### Output Report

Save to `{OUTPUT_DIR}/pm-reviews/`:

1. **PM Health Scorecard** (table above)
2. **Kill List** with justifications for each item
3. **Kano Distribution** (count of behaviors per level)
4. **OKR Coverage Gaps** (features without OKR links)
5. **Top 5 Recommendations** ranked by impact
6. **Issues by type** ([AI-FIXABLE] vs [NEEDS-HUMAN])

---

## Phase 6: Quality Iteration

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol:
- Target: `MIN_SCORE` from config (default 10)
- Max iterations: `MAX_ITERATIONS` from config (default 3)
- For each iteration: fix AI-FIXABLE issues, ask user about NEEDS-HUMAN
- Re-score after fixes
- Exit when score >= MIN_SCORE, or only NEEDS-HUMAN issues remain, or
  MAX_ITERATIONS reached

**Never inflate scores to exit the loop.** If issues remain, report honestly.

---

## Phase 7: Recommendations

After scoring and iteration, provide:

1. **Immediate actions** — things that can be fixed now (missing Kano levels,
   empty Gherkin, OKR links to add)
2. **Refinement pipeline run** — recommend which of the 12 LeanSpecs AI
   templates to run based on gaps found (see PM Philosophy Section 9).
   Typical post-review sequence: Musk Simplify → Strengthen Rationales →
   Suggest Kano → Generate Gherkin → Validate Hierarchy.
3. **QA canary test** — before running full-capability QA, test one behavior
   as a canary to catch infrastructure issues at cost 1 instead of cost N.
4. **Spec propagation checklist** — after spec changes, verify all consumer
   services have the updated product.json (push to GitHub + docker cp or
   reconnect for each consumer).
5. **Strategic recommendations** — structural changes (capability reorg,
   feature kills, scope reduction)
6. **Next quarter planning** — what OKRs should target based on gaps found
7. **Process improvements** — how to prevent these issues from recurring

End with the kill list prominently displayed. The kill list is the most
valuable output of a PM review.

---

# Cleanup Mode — execute the spec-cleanup playbook

Trigger when the user says "clean up spec", "spec cleanup", "fix iris-qa specs", "fix <product> specs", "migrate to layer template", "layer migration cleanup", or any equivalent phrasing that signals MUTATION intent rather than review.

## Phase A: Load the playbook

The single source of truth is the spec-cleanup playbook reference loaded in Phase 1 above. **Re-read it now if you skipped to Cleanup mode** — it has the 7-layer template, cap themes, smell tests, layer-migration recipe, CRUD pattern, one-test-per-behavior discipline, Gherkin generation red flags, and "When in doubt" questions.

```bash
cat ~/PycharmProjects/jjstack/references/spec-cleanup-playbook.md
```

Also scan the product's auto-memory directory for accumulated worker-specific feedback. For leanspecs:

```bash
ls ~/.claude/projects/-home-jesper-PycharmProjects-disciplin-run-leanspecs/memory/ \
  | grep -E "spec|gherkin|layer|kano|cleanup|shared|cap|gate"
```

Read every match before authoring. The user has paid for each of these rules in past sessions.

## Phase B: Survey the product

```python
mcp__leanspecs__spec_info(repo=<product>, branch=main)
mcp__leanspecs__spec_read(repo=<product>, branch=main, depth="list")  # whole tree, layers + cap shells
```

Identify:
- Schema version (v0 = pre-layer, v1 = post-layer). Migration may be needed.
- Layer distribution (caps per layer, what's in `unmapped`).
- Behavior count, status mix (draft vs approved vs review).
- Existing OKR/KR linkage rate.
- Visible vs hidden layers — empty layers should be hidden, populated ones visible.

If everything is in `unmapped`, this is a fresh layer-migration cleanup. Use the layer-migration recipe in the playbook.

If structure is mostly correct but smells are present (junk-drawer features, multi-scenario behaviors, descriptive feature titles instead of tool names), use the smell tests + cleanup sequence (Phases 1-10) in the playbook.

## Phase C: Plan before mutating

Write the plan to `~/.claude/plans/<product>-spec-cleanup-<date>.md`. Cover:
- Target cap structure (slot → name → Kano → which tools/features land here)
- Specific MCP calls in execution order (spec_create / spec_move / spec_merge / spec_reorder / spec_tidy / spec_update / spec_import)
- Capability-level Rule: gherkin lines per cap (one Rule per architectural invariant)
- OKR linkage strategy by cap (default rule from playbook)
- Deferred items (what stays in `unmapped`, what becomes a follow-up WO)

**Get user approval before mutating.** Show the plan, ask for go-ahead. Cross-worker dispatches require per-dispatch approval (see `feedback_ask_before_dispatching.md`).

## Phase D: Execute

Follow the layer-migration recipe in the playbook. Maintain a movement log file (`~/.claude/plans/<product>-spec-cleanup-movement-log.md`) capturing every move/rename — the product's code worker will need it to update test scaffolding.

## Phase E: Verify

```python
spec_read(item_id="<layer>", depth="list")  # one call per layer
spec_info(repo=<product>, branch=main)
spec_validate(repo=<product>, branch=main)
cleanliness_review(repo=<product>, branch=main)
```

## Phase F: Handoff

Draft a self-contained handoff message for the product's code worker (their context may have been cleared). Cover: new cap structure, tool-name renames the spec now expects, stale test scaffolding warning, suggested next steps, references to plan + movement log.

**Ask the user before sending.** Per the per-dispatch approval rule.

---

## Common mistakes to avoid (paid for in past sessions)

1. **Reinventing the playbook.** This skill loads `spec-cleanup-playbook.md` for a reason — read it before authoring. If a session-specific lesson is missing from the playbook, add it there (not as a one-off memory or duplicate skill).
2. **Duplicating memories.** Before writing a new memory file, `ls` the memory directory and grep for the topic. `feedback_one_mcp_tool_one_feature.md` already exists — don't write a new memory for the same rule.
3. **Cross-worker dispatch without approval.** Every tubemail message and every QM work order to another worker needs explicit per-dispatch approval. See `feedback_ask_before_dispatching.md`.
4. **Cap themes drifting from slot numbers.** The user expects `mcp:1 = Core`, `mcp:2 = Aux Lifecycle`, `mcp:3 = Help & Assist`, `mcp:4 = Foundation` by slot ID. If `spec_tidy` lands caps in the wrong slots, use `spec_reorder` + product-level `spec_tidy` to align — don't just rename labels.
5. **Spec-id tokens in narrative fields.** The `spec_id_in_text_field` gate rejects any `mcp:N`-style token in name / description / rationale / detail. Use the referenced item's current name.
6. **Stale rationale after restructure.** When you merge/move/split features, summaries get updated but rationales get stranded. Re-read rationales after any structural change.
7. **Trimming multi-scenario behaviors instead of splitting.** If a behavior carries multiple `Scenario:` blocks, the fix is to SPLIT into N sibling behaviors — never trim by keeping one scenario and discarding the rest. Each scenario is an approved contract. Folding scenarios into a feature-level `Rule:` compresses contracts out of existence; write the behavior instead. See the "Split, don't throw" recipe in `spec-cleanup-playbook.md` (under "One Behavior, One Test").
