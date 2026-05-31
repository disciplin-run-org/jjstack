---
name: qa-loop
description: |
  TDD loop between iris-qa (QA owner) and a product-code worker. iris-qa
  generates the failing test suite FIRST, raw output becomes the authoritative
  work order, the code worker implements to green, iris-qa reruns. Bidirectional:
  either iris-qa OR the product can be the subject (any ai-agents ecosystem
  member: leanspecs, iris-qa, quartermaster, tubemail, actuatrix).
  Trigger on: "QA loop", "TDD loop", "implement specs X Y Z via iris-qa",
  "iris-qa loop", "TDD via iris-qa", "fail-first then implement", "implement
  via iris-qa".
  Do NOT trigger for: browser QA on a deployed UI (use /qa or /qa-only),
  test-suite health audit (use /qa-review), or loading QA operational rules
  (use /jj-qa).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# qa-loop — TDD driven by iris-qa, routed by the Quartermaster

This skill codifies the QA-loop pattern as a state machine. The pattern is
product-agnostic: any product in the ai-agents ecosystem can be the subject,
and the loop runs the same shape every time. iris-qa-tm is always the QA
owner; the subject's code worker (`<product>-code-tm` or just `<product>-tm`
if there is no role split) implements to green.

## Subject vs role

Two roles, played by different workers:

- **SUBJECT** — the product whose code is being driven by failing tests.
  Could be `<product>-code-tm` (leanspecs has spec/code/ui split),
  `<product>-tm` (single-worker products), or even **iris-qa-tm** when its
  own generator/test-runner needs to be improved.
- **QA OWNER** — always `iris-qa-tm`. Generates failing tests, classifies
  failures, reruns after fixes.

Bidirectionality: today's QM #181 made iris-qa the subject — its generator
hardcoded `repo='test_repo'`, surfaced through a leanspecs qa-loop. Same
loop shape, different subject. iris-qa as subject still gets work orders
filed via QM, gets reviewed via the reviewer protocol below, etc.

## Phase 0 — dependency check (MANDATORY before any qa-loop scope fires)

For any qa-loop scope `<product>:<cap>.<feature>`, identify upstream caps it
implicitly depends on (e.g. `mcp:3.X` depends on `mcp:1`+`mcp:2`; UI scopes
depend on the underlying MCP scope). Run `iris_qa_run` on those FIRST.

A Phase 0 failure becomes its own qa-loop scope. The original scope waits
behind it.

**Rule:** never assume a cap is "done" from commit messages alone — iris-qa
is the only authority. Cite `feedback_verify_assumptions_before_qa_loop.md`.

## The non-negotiable order

**iris-qa goes FIRST.** The subject's code worker goes SECOND. Anything else
is not TDD.

```
1. iris-qa-tm    generates + runs the failing test suite for the scope
2. iris-qa-tm    classifies each failure into one of five buckets
3. Quartermaster receives the classified report
4. Quartermaster routes work orders:
                 target_bug    → subject's code worker (implements to green)
                 spec_quality  → subject's spec worker (sharpens Gherkin)
                 spec_gap      → subject's spec worker (creates new behavior in unmapped:1.1)
                 iris_qa_bug   → iris-qa-tm fixes its own generator
                 setup_bug     → fix the fixture host or sync infrastructure
5. Workers implement. Push to origin/main.
6. Sync product.json subject→iris-qa if Gherkin changed.
7. iris-qa-tm re-runs the scope. Loop.
8. Stop when pass rate reaches 100% OR plateaus for two cycles (escalate).
```

## What the dispatcher MUST NOT do

- **Do not paraphrase Gherkin into a work order.** The raw `iris_qa_run`
  output is the authoritative failure description.
- **Do not send the subject an implementation work order before iris-qa
  has produced failing tests.** Without failing tests, there is no TDD.
- **Do not ask "is this really what you want?" when the user says TDD.**
  The user authorized the loop. Failing tests ARE the work order.
- **Do not stop to confirm scope when the user listed the specs.** The
  list is the scope. Execute.
- **Do not classify failures without reading the raw pytest error.**
  "unmapped_step: True" can be tool-missing (target_bug) or bad step
  matcher (iris_qa_bug); only the raw error distinguishes them.
- **Do not let iris_qa_bug-class failures leak to the subject's code
  worker.** iris-qa owns its own generator.
- **Do not edit another product's source even with file access.** File a
  QM work order to the owning worker (per
  `feedback_role_boundaries.md`). Same rule whether iris-qa is subject or
  QA owner.
- **Do not narrow scope to dodge a tool timeout.** Timeouts mean the tool
  needs an async re-spec — see "When tools time out" below.

## The five failure buckets

| Symptom | Bucket | Route to |
|---|---|---|
| MCP tool doesn't exist / returns wrong shape | target_bug | subject's code worker |
| Tool times out under realistic load | target_bug | subject's code worker (async re-spec) |
| Gherkin vague, missing params, untestable, contradicts parent | spec_quality | subject's spec worker |
| iris-qa surfaces a real missing behavior (no spec exists) | **spec_gap** | subject's spec worker (create under `unmapped:1.1` "From iris-qa", `owner="iris-qa"`) |
| Generator produces unmapped_step on a legitimate tool call | iris_qa_bug | iris-qa-tm |
| Generator asserts wrong field / weak assertion / false pass | iris_qa_bug | iris-qa-tm |
| Generator hardcodes placeholders (`repo="test_repo"`) | iris_qa_bug | iris-qa-tm |
| Generator missing setup-prelude (e.g. for `spec_create(template=)`) | iris_qa_bug | iris-qa-tm |
| Generator collisions with new gates (e.g. `name_uniqueness_within_scope`) | iris_qa_bug | iris-qa-tm |
| Hardcoded ids that broke when spec ids migrated | iris_qa_bug | iris-qa-tm |
| Fixture wrong, dirty state, parent missing in fixture host | setup_bug | fix the fixture host |
| Container stale / product.json out of sync | setup_bug | sync infrastructure |
| Passes alone, fails in batch | setup_bug | retry-with-setup handles it |

`spec_gap` vs `spec_quality`: spec_quality fixes EXISTING Gherkin; spec_gap
files a NEW behavior because none existed.

### Cluster rule

When a scope returns >50% red, spot-check ONE generated test BEFORE
classifying. Generator bugs cluster — if one is wrong, they all are. Fix
the generator first; re-run.

### Spec-rename detector

When a cap or feature is renamed (e.g. Cap 12 → infrastructure:2,
mcp:3.20 → mcp:3.3), grep iris-qa source for the old id. Hardcoded
references silently break until something forces a regeneration.

## When tools time out

An MCP tool that times out under realistic test load (e.g.
`iris_qa_run(item_id="<cap>")` against a cap with 60+ behaviors hitting a
60s MCP client timeout) is a `target_bug`. File a work order on the owning
worker:

> Respec as async — return `job_id` immediately, expose `<tool>_status` for
> polling. BDD/TDD recode using the async-job pattern (model on
> `spec_import` mcp:3.10.1 or similar).

**Do NOT narrow scope to dodge the timeout.** That hides the architectural
bug. Cite `feedback_timeout_means_async_respec.md`.

## Tool semantics: `iris_qa_run` vs `iris_qa_run_suite`

- **`iris_qa_run(item_id)`** — GENERATES + runs tests for the given scope.
  Use this for first-time runs, or any time you want fresh tests. Per
  scope, not whole product.
- **`iris_qa_run_suite(scope)`** — READS disk only. Scores existing tests
  under `<workspace>/iris-qa/tests/generated/`. Never generates. Use ONLY
  after `iris_qa_run` has populated tests for the scope you want scored.

Returns since QM #163: `iris_qa_run_suite` now surfaces
`approved_behaviors` and `generated_tests` counts and emits a structured
error when approved>0 but generated==0, instead of silent
`tested_behaviors=0`.

## Reviewer protocol — if you sent it, you validate it

When a worker replies on a QM work order with `awaiting_review`, the
dispatcher (you) owns the verification. Five-step ladder before
`qm_queue_mark(status="done")`:

1. **Commit exists** at the claimed sha (`git -C <repo> show <sha>`).
2. **Diff matches** the claim's scope and line count.
3. **Docstrings/tests updated** where the claim says so.
4. **Live smoke** against the changed surface returns the new shape (e.g.
   call the changed MCP tool and confirm the response).
5. **Unit-suite claim** spot-checked (run a subset locally if feasible).

Any gap → `qm_queue_mark(status="needs_correction", reason="<specific
gap>")`. Don't pile orthogonal bugs onto the closing item — those go in
new QM items (today's QM #182 demonstrates the pattern).

**Trust but verify**: prose says what they intended; commit + diff + smoke
say what landed. The mismatch is where bugs hide. Cite
`feedback_dispatcher_owns_validation.md`.

### The same ladder applies BEFORE filing needs_correction

When a worker's reply has `verdict=partial` or `verdict=in_progress`, the
instinct is to send a corrective continuation. Before you do, run the
ladder one more time — specifically step 1 (commit exists) and step 2
(diff matches). The phrase "fix is in flight" in worker prose may mean
"already pushed to origin/main, you missed it" — and a corrective
direction asking the worker to undo work they've already shipped becomes
a wasted dispatch slot, plus a confused worker.

The check before correction:
- `git -C <worker-repo> log --oneline -10` — what's landed since
  dispatched_at?
- Read each new commit's message — does it explain what they did and why?
- If the shipped reasoning disagrees with your correction, decide whether
  their reasoning is actually better than yours BEFORE pushing back.

Caught 2026-05-06 on QM #181 → #185: the worker had already shipped
commit 23d6663 with a litmus-hardcode that contradicted my #185
correction. Their reasoning was sound; my correction would have asked
them to undo working code. The recourse was deletion, which is a worse
audit row than `done`. Cite `feedback_verify_before_correction_too.md`.

## Output discipline

**One PR per qa-loop scope.** Title: `feat(qa-loop): <scope> green`. The
worker that pushes red→green opens the PR. iris-qa-tm's generated-test
commits ride along on the same branch when the same scope produced both.

When multiple `<product>-<role>-tm` workers share one git tree (leanspecs
has spec-tm / code-tm / ui-tm), `git diff --staged --stat` before any
commit. Per `feedback_shared_worktree_commit_hazard.md`.

## Fixture isolation

Every qa-loop subject names a **fixture host** — a repo or workspace whose
product.json holds the test sandboxes. Fixture data lives in the host;
NEVER in the subject's live workspace.

Examples (not mandates):
- **leanspecs + iris-qa**: host is the `litmus` repo at `mcp:100+`. They
  share a spec schema, so they share a fixture pattern.
- **Other products** (quartermaster, tubemail, actuatrix, etc.): each
  picks the pattern that isolates fixture mutations from live state. Could
  be a per-product fixture repo, ephemeral docker volumes, in-process
  state, or anything else that achieves isolation.

The skill enforces "fixtures live in the host, never in the subject's live
workspace" — the host's identity is per-product, NOT a hard mandate.

## Setup contract source of truth

Each subject's setup/teardown sequence lives in its own spec at
`infrastructure:2` (or equivalent — read each subject's product.json to
find its QA Specs cap). iris-qa reads this on every run. If the subject's
setup spec drifts from what iris-qa is hardcoded to read, dispatch a
target_bug to iris-qa-tm to update its reader. Today's QM #181 included
this fix (Cap 12 → infrastructure:2).

## Infrastructure sync sequence

After ANY Gherkin change in the subject's spec, before running iris-qa:

```bash
docker cp ai-agents-<product>-1:/data/<product>/specs/product.json /tmp/p.json
docker cp /tmp/p.json ai-agents-iris-qa-1:/data/<product>/specs/product.json
```

Skip = stale tests, wasted cycle. Sync only after the spec change has
landed in the subject's container — not before.

## Canonical work orders

### To iris-qa-tm (the first cycle and every subsequent cycle)

```
Work order — Run iris_qa_run on <scope> and classify failures.

## Scope
<comma-separated feature ids or single item id>
target_url: http://localhost:<port>/mcp/?repo=<fixture-host-repo>
subject: <product> (whichever product is being driven this cycle)

## Deliverables
1. Verify product.json matches the subject's container. Sync if drifted.
2. iris_qa_run(item_id) for each scope item.
3. Classify each failure (target_bug / spec_quality / spec_gap / iris_qa_bug / setup_bug).
4. Fix iris_qa_bug-class failures in your own codebase; rebuild; retest.
5. Report in the shape:
   { scope, total, pass, fail, by_bucket, report: [{behavior_id, pass, bucket, diagnosis}, ...] }
```

### To the subject's code worker (after iris-qa reports target_bug failures)

```
Work order — Make <N> failing iris-qa tests green.

## Failing tests (from iris-qa-tm report <event_id>)
<paste the raw per-behavior failure lines>

## Deliverables
1. Implement the MCP tool(s) / fix the return shapes so every listed behavior passes.
2. Unit tests alongside (pytest).
3. docker compose up -d --build <product>.
4. Sync product.json to iris-qa: docker cp ... (the infrastructure sync sequence above).

## Verify
iris_qa_run(<scope>) — all listed behaviors pass.

## Done
Reply with: commit_sha, tests_passing, any remaining failures you classified differently. Open the PR titled `feat(qa-loop): <scope> green`.
```

### To the subject's spec worker (after iris-qa reports spec_quality OR spec_gap failures)

```
Work order — Fix <N> behaviors flagged by iris-qa.

## Flagged specs (from iris-qa-tm report <event_id>)
<paste flagged behavior ids + iris-qa's diagnosis>

## Deliverables (per item)
- spec_quality: rewrite Gherkin per `feedback_gherkin_patterns.md`.
- spec_gap: spec_create under `unmapped:1.1` "From iris-qa" with owner="iris-qa", rationale + summary + detail describing what iris-qa surfaced.

## Done
Reply: commit_sha, list of fixed/created spec ids.
```

## Gherkin quality rules (operational lessons)

- Every step maps to an explicit MCP tool call, not state description.
- Include ALL required parameters (owner, rationale for spec_create).
- "contains" for substring match, "equals" for exact match.
- Given steps VERIFY state with read tools, never CREATE data.
- Destructive tests (product_delete) restore the fixture host in And steps after Then.
- Behaviors that return confirmation text need a follow-up read for verification.

## Stop conditions

The loop ends when any one is true:
1. Scope is 100% green (goal state).
2. Pass rate did not improve across two consecutive cycles (routing
   misclassified or real blocker; escalate to user with a diff of the
   two cycles' reports).
3. A worker reports a classification change you disagree with — bring it
   to the user for arbitration before re-routing.

## Parallelism

iris-qa test generation and subject implementation are independent once
iris-qa's report is in. Multiple scopes can be in different phases
simultaneously:

- 3.1: iris-qa-tm running tests (cycle N)
- 3.3: subject's code worker implementing (from cycle N-1 report)
- 3.4: iris-qa-tm rerunning (verifying cycle N-1 fixes)

Dispatch all phases that are runnable; don't serialize artificially.

## Memory cross-references

Foundational:
- `feedback_tdd_non_negotiable.md` — approved behaviors must be testable; no "Not MCP-testable" dodges.
- `feedback_qm_is_manager.md` — QM directives are engineering-manager work orders; act, don't reconfirm.
- `feedback_align_gherkin_to_tool_schema.md` — load actual tool schema before rewriting gherkin.
- `feedback_retro_2026_04_14.md` — Cap 1/Cap 2 retro: TDD pushback, drift checks, Gherkin patterns.
- `feedback_role_boundaries.md` — bugs in another product's codebase = that product's worker; file QM work order, don't edit.

Operational (today's saves):
- `feedback_shared_worktree_commit_hazard.md` — diff before commit.
- `feedback_litmus_lives_in_litmus_repo.md` — leanspecs/iris-qa example of fixture host.
- `feedback_verify_assumptions_before_qa_loop.md` — Phase 0 sanity gate.
- `feedback_qa_loop_ecosystem_wide.md` — bidirectional, product-agnostic.
- `feedback_dispatcher_owns_validation.md` — five-step reviewer ladder.
- `feedback_timeout_means_async_respec.md` — timeouts = target_bug, not workaround.

## Philosophy

The QA-loop is a state machine, not a to-do list. The job is to keep the
state machine moving — route each classified failure to exactly the
worker who owns that class of bug, validate every reply against the
five-step ladder, keep infra synced, and let TDD's natural ordering (test
first, code second) do the sequencing. When the dispatcher tries to
shortcut — paraphrasing Gherkin, sending implementation work before tests
exist, narrowing scope to dodge timeouts, rubber-stamping awaiting_review
without verification — errors compound and the loop slows. Trust the
loop. Run it.
