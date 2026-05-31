---
name: qa-review
version: 0.1.0
description: |
  Adversarial audit of the test suite across 8 dimensions: Kano depth,
  test-type balance, production verification, failure triage, regression
  gates, test quality (mutation score), AI/MCP traps, infrastructure
  health. Loads the full QA philosophy. Audits whether the tests catch
  bugs, not whether they exist.
  Trigger on: "QA review", "test health", "test audit", "are our tests
  good enough", "QA score", "regression health", "mutation score",
  "test coverage audit", "QA check", "audit the test suite".
  Do NOT trigger for: browser QA execution (use /qa or /qa-only), TDD
  loop between iris-qa and a code worker (use /qa-loop), or loading QA
  operational rules (use /jj-qa).
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

# QA Review

QA health audit. Tests exist to catch bugs — this skill checks whether they
actually do. Coverage numbers lie. Mutation scores don't.

## Phase 1: Load QA Knowledge

Load these references in order. Read each file in full.

**1. QA Philosophy:**

```bash
cat ~/.claude/skills/jjstack/references/qa-philosophy.md
```

**2. Unit Test Philosophy:**

```bash
cat ~/.claude/skills/jjstack/references/unit-test-philosophy.md
```

**3. Kano Model (test depth floors):**

```bash
cat ~/.claude/skills/jjstack/references/kano-model.md
```

**4. jjstack config:**

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

Then check for project override:

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store: `MIN_SCORE` (default 10), `MAX_ITERATIONS` (default 3), `OUTPUT_DIR`.

**5. Load DNA (if configured):**

Read `dna.voice` and `dna.coding` paths from config. Apply to all output.

---

## Phase 2: Understand the Test Suite

Before reviewing, understand what you're reviewing.

### 2.1 Identify the product

Use AskUserQuestion if not obvious:
- What product are we reviewing?
- Where are the tests? (`tests/`, `debug/`, other?)
- Is there a LeanSpecs spec with Kano levels?
- Is there an iris-qa setup?

### 2.2 Read the test landscape

```bash
find . -name "test_*.py" -o -name "*_test.py" | head -50
```

Read `pyproject.toml` for test config (pytest, mutmut, hypothesis settings).
Read `conftest.py` files for fixture architecture. Read `debug/heal.py` if
it exists.

### 2.3 Get current metrics

If available, gather:
- Test count and pass rate
- Coverage percentage (if measured)
- Mutation score (if mutmut configured)
- Last E2E test run date/result
- Regression-locked test count

---

## Phase 3: The QA Persona

Adopt this voice for the entire review:

> You are a QA architect who has seen every test anti-pattern and knows
> that coverage numbers lie. You care about whether the tests actually catch
> bugs, not whether they exist. You've debugged production incidents where
> 100% unit test coverage missed the problem because nobody wrote an E2E
> test. You've seen teams with 500 tests and zero confidence, and teams
> with 50 tests and total confidence. The difference is whether the tests
> answer the right questions. You're relentless about the right test for
> the right question.

---

## Phase 4: Review — 8 Scored Passes

Each pass is scored 0-10. For each dimension:
1. State the score
2. Cite specific evidence (test files, behaviors, gaps)
3. List issues as **[AI-FIXABLE]** or **[NEEDS-HUMAN]**
4. Provide concrete recommendations

### Pass 1: Kano Test Depth Compliance (0-10)

- Does every behavior have at least one test?
- Does test depth meet the Kano minimum floor?
- Are Kano 1-2 (Security/Core) getting exhaustive coverage?
- Are Kano 1 behaviors tested with 100% use + 100% corner cases?
- Is anything tested below its floor?
- Are the Kano floors treated as minimums (not targets)?

**Red flags:** Behaviors with no tests. Kano 1-2 behaviors with only happy-
path tests. Kano levels missing from the spec (can't determine required
depth). Test depth treating floors as ceilings.

### Pass 2: Test Type Balance (0-10)

- Testing trophy shape: static → integration → E2E → exploratory?
- Is the project over-indexed on unit tests with no E2E?
- Are MCP tool calls tested as integration tests?
- Is there at least one E2E test exercising the full pipeline?
- Right test type for the right question?
- Static analysis running (linting, type checking)?

**Red flags:** 200 unit tests, 0 E2E tests. MCP tools only tested via
mocked unit tests (never called as integration). No static analysis in
CI. Load tests for a CRUD app, no security tests for an auth service.

### Pass 3: Production Verification (0-10)

- Is there canary/post-deploy verification?
- Health checks running against production?
- Rollback criteria predefined (error rate, latency thresholds)?
- Smoke tests run after every deploy?
- "Production truth > staging confidence" — is this practiced?
- Production observability: error rates, latency, business metrics?

**Red flags:** No post-deploy verification. "It works in staging" accepted
as proof. No rollback criteria. No production monitoring. Manual "click
around and see if it works" as the only post-deploy check.

### Pass 4: Failure Triage Discipline (0-10)

- Are test failures classified into four buckets?
  (target_bug / spec_quality / iris_qa_bug / setup_data)
- Is routing correct (product worker / QA worker / orchestrator)?
- Are spec_quality failures fed back to PM for spec refinement?
- Is setup_data being prevented (not just triaged)?
- Are LLM transients retried before classification?

**Red flags:** All failures treated as "fix the test." No triage discipline.
spec_quality failures silently fixed in tests instead of escalated to PM.
setup_data failures recurring because nobody fixes the environment. Flaky
tests ignored instead of quarantined.

### Pass 5: Regression Gate Health (0-10)

- Are regression-locked tests protected from breakage?
- What's the current pass rate vs gate thresholds?
- LAUNCH/HALT gate: is it binary (no DEGRADED compromise)?
- Are quarantined tests being resolved (not parked forever)?
- Dual-axis grading: per test_target and test_scope?

**Red flags:** Regression-locked tests being deleted to make CI green.
"DEGRADED" accepted as a ship state. Quarantined tests older than 2 sprints.
No per-target breakdown (hiding security failures behind API pass rate).

### Pass 6: Test Quality — Not Just Coverage (0-10)

- Mutation score (mutmut): surviving mutants?
- Property-based testing (Hypothesis): used where valuable?
- Test smells present? (tautological, over-mocking, brittle, copy-paste)
- Tests follow coding DNA standards (same quality as production code)?
- Adversarial thinking applied (boundary analysis, negative tests)?
- Error messages assert specific text (not just error type)?

**Red flags:** No mutation testing. Tautological tests (assert what code
literally does). Over-mocking (more mock setup than test logic). Tests
exempt from coding DNA. Only happy-path tests. Error tests check exception
type but not message content.

### Pass 7: AI/MCP-Specific QA (0-10)

- Tool schema regression tested (descriptions, parameter shapes)?
- LLM chaos input testing for MCP tools?
- Prompt regression suites for AI-generated outputs?
- Confused deputy / privilege boundary tested?
- Command injection via tool parameters tested?
- mcp-scan or equivalent run against MCP servers?
- AI-generated code reviewed (not blindly trusted)?
- Non-deterministic outputs evaluated statistically?

**Red flags:** No schema regression tests. MCP tools accept any input
without validation. No privilege boundary tests. AI-generated tests trusted
without mutation testing. Deterministic pass/fail on non-deterministic output.

### Pass 8: QA Infrastructure Health (0-10)

- Heal framework exists and captures fixes?
- Tests run in Docker (not local processes)?
- QA cleans up after itself (no leftover test data)?
- CI pipeline includes QA gates?
- Test execution time reasonable (fast feedback)?
- Test data management: fixtures, factories, not mystery guests?
- Flaky test management: quarantine, don't ignore?

**Red flags:** No heal framework (ad-hoc debugging). Tests run against local
services. Leftover test data in databases. No CI gate (tests are optional).
Test suite takes > 10 minutes for unit tests. Flaky tests accepted as normal.

---

## Phase 5: Scoring & Report

### QA Health Scorecard

| # | Dimension | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Kano Test Depth | /10 | |
| 2 | Test Type Balance | /10 | |
| 3 | Production Verification | /10 | |
| 4 | Failure Triage | /10 | |
| 5 | Regression Gates | /10 | |
| 6 | Test Quality | /10 | |
| 7 | AI/MCP QA | /10 | |
| 8 | QA Infrastructure | /10 | |
| | **Overall QA Health** | **/10** | |

Overall = average of 8 dimensions.

### Output Report

Save to `{OUTPUT_DIR}/qa-reviews/`:

1. **QA Health Scorecard** (table above)
2. **Test Depth Gap Analysis** (behaviors below Kano floor)
3. **Mutation Score Report** (if mutmut available)
4. **Regression Gate Status** (pass rates by target × scope)
5. **Test Kill List** (tests to delete: flaky, tautological, duplicate,
   over-mocked, testing the framework instead of the product)
6. **Top 5 Recommendations** ranked by impact
7. **Issues by type** ([AI-FIXABLE] vs [NEEDS-HUMAN])

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
- Exit when score >= MIN_SCORE, or only NEEDS-HUMAN remain, or
  MAX_ITERATIONS reached

**Never inflate scores to exit the loop.**

---

## Phase 7: Recommendations

After scoring and iteration, provide:

1. **Immediate actions** — tests to write now (Kano floor gaps, missing E2E,
   missing schema regression)
2. **Mutation testing run** — if not done, recommend running mutmut and
   provide the pyproject.toml config
3. **Triage setup** — if four-bucket triage not in place, describe how to
   implement
4. **Production QA plan** — canary criteria, health checks, monitoring
5. **Heal framework** — if none exists, recommend `/heal` to create one
6. **Test kill list** — prominently displayed. Bad tests are worse than no
   tests because they create false confidence.

End with the test kill list. Deleting bad tests is as valuable as writing
good ones.
