# Spec Cleanup Playbook

Adversarial product management review for a single capability. Turn a junk-drawer capability into crisp, testable specs ready for the QA loop. Derived from the Cap 2 cleanup session for LeanSpecs.

**Who uses this:** the resident Product Manager (AI or human) preparing a capability for the iris-qa loop. The upstream assumption: the QA loop will amplify whatever you feed it — bad specs produce bad tests which bake wrong behavior into code.

**Scope:** one capability at a time. Don't try to clean two caps in parallel — the moves between caps make it confusing.

---

## The five smell tests

Apply these in order. Each one is a reason to fix something.

### 1. Name smell
A capability name that means "everything that isn't X" is not a capability — it's a dumping ground. Examples: "MCP Auxiliary", "Utilities", "Miscellaneous", "Extras".

**Fix:** strip away the misplaced items and see what coherent identity emerges. Rename to reflect that identity. If no identity emerges, the capability shouldn't exist.

### 2. Size smell — the 18-behavior feature
A feature with more than ~6 behaviors is almost always doing multiple unrelated things. A feature with 10+ is a junk drawer.

**Fix:** group behaviors by actual domain, split into multiple features.

### 3. Duplication smell — the same thing said 3 ways
If three behaviors describe the same rule in different words, the QA loop will generate three tests that either conflict or redundantly test one code path.

**Example from Cap 2:**
- 2.5.1 "Approval is computed from data completeness"
- 2.6.1 "Status is computed from data, not manually transitioned"
- 2.6.5 "Computed status is a pure function of item data"

All three said the same thing. Merged into one.

**Fix:** merge, keep the clearest wording, delete the rest.

### 4. Domain misplacement smell
A behavior's name contains clues to its real home:
- `github_save`, `github_status` → likely not core CRUD
- "UI button", "Debug tab", "displays" → likely UI capability
- "CLAUDE.md", "governance", "convention" → likely not product functionality at all (might belong in a .md file)
- "KPI Generator is a separate tool" → the behavior is itself declaring it doesn't belong here

**Fix:** move to the right capability. Don't silently drop — the user said the behavior is important even if misplaced.

### 5. Overstep smell — two tests in one behavior
If a single behavior describes both a happy path and an error path, it's two tests.
If it describes both a write action and a read action, it's two tests.
If it describes setup and verification as separate assertions, check for two tests.

**Example from Cap 2:**
- Original 2.1.1: "Loads product.json... Fails fast with specific error if configuration is missing"
  - Happy path: loads successfully
  - Error path: fails with specific error
  - Two tests — split.

**Fix:** split. One behavior = one scenario = one testable assertion.

---

## Capability-level framing

Every product spec in the ecosystem follows the Kano-aligned template. Place every feature accordingly:

| Cap | Kano | Role | Litmus test |
|-----|------|------|-------------|
| 1 | 1-2 | Core | Product is broken without it |
| 2 | 3 | Aux | Product works but is tedious/manual without it |
| 3 | 4+ | Extended (PM assist) | Product works but user has to figure things out |
| 4 | 6 | CLI | Intermediate interface (may be deliberate "no") |
| 5 | 5 | Web UI | Delighter interface |
| 6 | 5 | Shared components | Platform library opt-ins |
| 7 | 8 | Debug | Operator diagnostics, not daily user use |
| 10 | — | Technical Specifications | Infrastructure, security, testing ADRs |
| 11 | — | Design Specs | UI/UX rules |
| 12 | — | QA Specs | Test setup/teardown/contract |

**Deliberate "no" capabilities:** if you've decided NOT to build something, that's a Kano 6 ("Less is More") decision and deserves a capability with no features, just a description explaining the decision. Example: Cap 4 "CLI — no CLI at this time, all interaction via MCP API or Web UI."

**Capability backup analogy (from kano-model.md):**
- Cap 1 = make a single backup right now
- Cap 2 = schedule the backup to run at night
- Cap 3 = intelligence that suggests what to back up

---

## Global vs workspace vs session — the scope trap

State-management behaviors frequently mix scopes. Untangle them:

| Scope | Examples | Where it lives |
|-------|----------|---------------|
| Global (user-level) | OAuth token, AI model, API key, Writing DNA | One feature under Aux |
| Per-workspace | Current repo, branch, spec path, push mode | Separate feature under Aux |
| Per-session | MCP transport state | Tech specs (Cap 10) |

**Symptom of the trap:** one `settings_update` tool that writes both global and per-workspace fields, causing confusion when 4 browser windows have 4 different workspace configs.

**Fix:** split into two tools (settings_read/update for global, workspace_settings_read/update for per-workspace). Or at minimum, separate the spec behaviors so each one is unambiguous about scope.

---

## CRUD pattern for CRUD-like features

For features that are fundamentally "CRUD on an MCP tool," follow the Cap 1 pattern:
- **One feature = one MCP tool.** The feature is named after the tool (spec_create, spec_read, etc.).
- **Behaviors = parameter variations + edge cases.** Each behavior tests one invocation pattern.
- **Sort order:** Create → Read → Update → Delete at the feature level.

When a feature's behaviors don't map to a single tool (e.g., a feature with github_save + github_status + github_repos), that's a smell — it's probably multiple features in one.

---

## One-test-per-behavior discipline

Every behavior must be testable by exactly one test scenario. Indicators that a behavior is overstuffed:

- Contains "and" or "or" joining two distinct operations
- Describes preconditions AND action AND verification AND error handling
- Would require multiple assertion groups in the Gherkin

**When splitting:** one behavior per outcome. For outcome-driven operations like scoring, each outcome is its own test:
- Scoring: achieved (all met), partial (some met), missed (none met), error (dependency unreachable) = 4 behaviors

---

## Feature-level Gherkin is stale by default

When cleaning a capability, **wipe all Gherkin at every level** before rewriting. Gherkin written months ago often describes the system as it was imagined, not as it is. The QA loop will generate bad tests from stale Gherkin.

**Process:**
1. Delete all Gherkin fields under the capability (use bulk wipe if the tool supports it)
2. Fix structure (moves, merges, deletes)
3. Regenerate Gherkin at the end, once structure is stable

---

## Not MCP-testable flagging

Not every behavior can be tested by iris-qa in the litmus sandbox. Flag infrastructure behaviors explicitly so iris-qa skips them:

Format in detail field:
```
<existing detail>

Test operates in litmus capability N ("Sandbox for X.Y.Z"). Not MCP-testable: <reason>.
```

**Reasons to flag:**
- Container startup behavior (can't test from inside a running container)
- Interactive OAuth flows (require browser)
- External service dependencies (Actuatrix KPI integration, GitHub API)
- Multi-session collaboration (requires concurrent workspaces)
- Global/workspace-level state (not sandbox-scoped)
- Infrastructure changes that require container rebuild

**What remains testable:** operations on items within a sandbox capability — CRUD, audit, validation, local state.

---

## The cleanup sequence

Execute in this order. Skipping steps creates rework.

### Phase 0 — Load context
1. Read `kano-model.md`, `product-management.md`, and this doc
2. Read the current capability (`spec_read item_id=N`) and scan for the five smells
3. Read Cap 1 (the reference cap) to remember the clean pattern
4. Look at sibling capabilities that might receive moved behaviors

### Phase 1 — Wipe stale Gherkin
- Delete Gherkin field on capability, every feature, every behavior under it
- This prevents the QA loop from generating bad tests from stale content

### Phase 2 — Delete and move
- Soft-delete truly redundant behaviors (with note explaining which survivor covers them)
- Soft-delete convention behaviors that belong in .md files, not specs
- Move behaviors to their natural home capability
- If a behavior describes an MCP tool variant of another feature (e.g. bulk_update vs spec_update), kill it if optional, merge it if essential

### Phase 3 — Merge and consolidate
- Merge features that describe one domain split across two (e.g., OKR + KPI)
- Consolidate duplicated concepts (the "3 ways to say computed status" smell)
- Rename junk-drawer features to reflect their actual contents after cleanup

### Phase 4 — Split oversteps
- For each remaining behavior, check one-test discipline
- Split any behavior describing happy + error paths, write + read, or multiple outcomes
- Add new behaviors for edge cases that were implied but not written (e.g., concurrency conflicts, missing config)

### Phase 5 — Regroup what remains
- If the starting capability still feels wrong, extract new features
- Create sibling features for orthogonal concerns (Global Configuration vs Workspace Configuration)
- Rename the capability if the cleanup revealed a sharper identity

### Phase 6 — Tidy IDs and verify
- Run `spec_tidy` on the capability
- Confirm no active behavior has been silently dropped (compare before/after behavior list)
- Verify every feature has 2-6 behaviors; larger features are still junk drawers
- Verify the capability has a one-sentence identity that answers "what job does this do?"

### Phase 7 — Triage for testability
- For each behavior, decide: MCP-testable in litmus sandbox, or flag as infrastructure?
- Default to flagging aggressively — better to skip a test than to write a bogus one
- Flag reasons in detail field so iris-qa can skip them

### Phase 8 — Regenerate Gherkin
Use `ai_suggest_field(field="gherkin")` for every behavior, then evaluate:

**Accept** when the suggestion is a single scenario that matches summary + detail.

**Reject and diagnose** when any of these red flags appear:
- **AI Gherkin contradicts the summary or detail.** Means the rationale (or some other field) is stale. Fix the stale field, regenerate.
- **AI output contains multiple Given/When/Then blocks.** The behavior needs to be split — multi-scenario Gherkin is a smell, not a feature. Create new behaviors, regenerate each.
- **Summary contains "X, Y when offline" or "validates: A, B, C" patterns.** The AI will expose these as multi-scenario output. Split the behavior on that split point.

For testable behaviors, write or accept Gherkin following the Cap 1 pattern:
- Every step is an explicit MCP tool call
- `spec_create` calls include `owner="qa-tester", rationale="test"`
- Given steps verify preconditions via `spec_read` (or create test data)
- Use `contains` for substring match, `equals` for exact match
- Use "the response confirms the X" for non-JSON confirmations
- One Scenario per behavior — no multi-scenario Gherkin

For Not-MCP-testable behaviors, the AI-generated descriptive Gherkin is acceptable as documentation.

Add litmus cap reference to the detail: `Test operates in litmus capability N ("Sandbox for X.Y.Z"). <fixture description>.`

### Phase 9 — Expand litmus fixture (code change)
For each testable behavior, add its sandbox capability to `LITMUS_FIXTURE` in `src/leanspecs/mcp_specs.py`. Pre-populate any data the Gherkin's Given steps assume (feature names, behavior summaries, specific kano levels, parent gherkin, etc.).

### Phase 10 — Commit and push
- `github_save` the spec changes (or commit product.json directly in direct mode)
- Commit the fixture code change separately
- Push to main (or create PR per project push_mode)

---

## Red flags during cleanup

Stop and re-examine if you see any of these:

- **You're about to delete a behavior outright.** Unless it's a true duplicate, it probably belongs somewhere. Move, don't delete.
- **You're about to create a 5th sibling feature for the same domain.** That's over-splitting. Step back and see if 2-3 coarser features capture the same content.
- **A behavior's description mentions a tool that doesn't exist in the codebase.** Check if the tool was renamed, deprecated, or was always aspirational. Update accordingly.
- **A feature's name ends with "Management" or "Handling" or "Operations".** These are weak nouns hiding the real identity. Rename to something concrete.
- **The QA loop has flagged the capability in a previous run.** Treat prior QA feedback as load-bearing signal about which behaviors were actually untestable.

---

## When in doubt

Ask:
1. What job does this capability do for the user?
2. If this behavior didn't exist, would the product be broken (Cap 1), tedious (Cap 2), or less helpful (Cap 3)?
3. Can one test verify this behavior completely?
4. Does the name of this behavior tell you which MCP tool to call?
5. Is the description of what the code does, or of what the user experiences?

If the answer to any of these is unclear or surprising, there's more cleanup to do.

---

## Output of a good cleanup

After Phase 6:
- Capability has a one-sentence identity.
- Features: 5-10 per capability, each with a clear single-tool-or-concept focus.
- Behaviors: 2-6 per feature, each a single testable statement.
- No duplicates. No two behaviors saying the same thing.
- All Gherkin empty (will be regenerated in Phase 8).

After Phase 8:
- Every testable behavior has one Scenario Gherkin.
- Every untestable behavior is flagged with a reason.
- Litmus fixture supports every testable Gherkin's preconditions.

After Phase 10:
- Ready for the iris-qa loop to generate tests.
- The QA loop can distinguish spec_quality failures from target_bug and iris_qa_bug.

---

## AI-assisted Gherkin generation — round lessons

### The AI is a smell detector, not just a writer

When you run `ai_suggest_field(gherkin)` on every behavior in a capability, rejections tell you more than accepts. Every rejection points to a bug in the behavior itself, not in the AI:

- **Gherkin contradicts summary/detail** → rationale or some other field is stale. Common after capability restructuring where fields got stranded.
- **Multi-scenario Gherkin output** → behavior is overstuffed. Each scenario wants to be its own behavior.
- **Vague/generic Gherkin** → the behavior's detail is too thin for the AI to generate anything specific. Detail needs sharpening.

Treat rejections as diagnostic signal, not failure. Log each rejection with its reason so you can look for patterns across capabilities.

### Stale rationale is the #1 post-restructure smell

When you move, merge, or split features during cleanup, summaries and details usually get updated. **Rationales get stranded**. Then AI generates Gherkin that matches the stale rationale, contradicting the current summary. Symptoms:

- Summary says "loads from selected branch", rationale says "always loads from default"
- Detail says "Actuatrix owns KPIs", rationale says "LeanSpecs stores KPI library"

Fix: after any merge/move/split, re-read the rationale. If it starts with "Users select a branch to work from (e.g. a feature branch), BUT specs are always loaded from the default branch" — the "but" clause is the smell. Rewrite.

### Multi-scenario output = behavior that wants to be split

If the AI produces 2+ Scenario headers or 2+ Given-When-Then triads, the behavior is 2+ behaviors in disguise. Don't flatten the Gherkin — split the behavior. Patterns that produce this:

- Summary with comma-joined clauses: "displays X, Y when offline"
- Summary with list-joined clauses: "validates: repo, branch, token, path"
- Detail describing multiple error modes of the same operation

Each clause becomes its own behavior with its own single-scenario Gherkin.

### Automate the detection, not the judgment

Multi-scenario detection and field contradiction are deterministic problems. They don't need AI — they need Python regex over Gherkin strings. Build these as blockers at the suggestion-storage layer:

- Count `Scenario:` headers: if > 1, return `split_required: true`
- Detect `Given` after `Then` without intervening `Scenario:` header
- Extract keywords from summary/detail/rationale and check them against Gherkin for negation mismatches

Blocking (refuse to store) is better than warning (store with flag), because a human reviewer will accept multi-scenario Gherkin if only warned, then the bad spec ships.

**Algorithm first, inference last applies directly here:** the 6 Python lines that count Scenario headers replace hours of human eyeball review.

### Flag aggressively on "Not MCP-testable"

On the first pass of a capability, you'll flag the obvious infrastructure behaviors (container startup, OAuth flows, external service deps). On the second pass after closer review, you'll find 2x more:

- Anything requiring actual branches, repos, or tokens at the GitHub level
- Anything requiring 2+ concurrent sessions
- Anything reading/writing global or workspace-level state (not sandbox-scoped)
- Anything requiring un-cloned state or fresh-machine state

**Rule of thumb for Aux capabilities:** expect ~80% of behaviors to be Not MCP-testable. That's fine. Aux is infrastructure glue. The QA loop tests the 20% that operates inside the sandbox. The 80% still gets documentation Gherkin for human readers.

### Orchestrated work orders need scope-check

When an orchestrator sends a work order with a specific behavior count and cap mapping, the count is usually optimistic. Do the judgment pass BEFORE executing:

1. Read each behavior the orchestrator wants you to test
2. For each, ask: "can this actually run in the litmus sandbox without external deps?"
3. Report back the revised testable count before writing Gherkin
4. Don't Gherkin behaviors that can't actually run — you're producing noise

### The playbook is self-referencing

Once this playbook lists Gherkin-generation smells (this section), you can use LeanSpecs itself to propose new behaviors for detecting those smells. The detection behaviors go into Cap 3.11 Gherkin Generation of the LeanSpecs product spec. Then when we rebuild, the tool enforces its own rules on itself.

When working on a new capability, load this playbook first, then `ai_suggest_field(gherkin)` each behavior. The workflow enforces the smell tests automatically.
