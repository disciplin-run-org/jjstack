# QA Philosophy

The unified QA knowledge base for the dev ecosystem. Ties together unit
testing (`unit-test-philosophy.md`), operational rules (`/jj-qa`), debug
frameworks (`/heal`), and fills the gaps: test type taxonomy, production QA,
AI/MCP agent testing, and the iris-qa test generation model.

For unit test specifics (adversarial thinking, boundary analysis, mutation
testing), see `references/unit-test-philosophy.md`. For operational rules
(cleanup, Docker-first, Kano depth table), see `/jj-qa`. This document is
the strategic layer above both.

---

## 1. JJ's Rules of QA

Four rules from the coding DNA, expanded with practical application.

### Rule 1: E2E is what the customer needs. Unit tests nail regressions.

The customer does not care that your unit tests pass. They care that the
product works. Unit tests are for developers — they catch regressions early
and localize failures. E2E tests are for customers — they prove the system
delivers value.

**Practical application:** Every product must have at least one E2E test that
exercises the full pipeline with realistic data. If the E2E test passes, the
product works. If it fails, binary-search fault isolation finds the broken
component. Never ship with unit tests only.

### Rule 2: Production truth > staging confidence > local hope.

Staging increases the probability that production will work, but it is not
proof. The ultimate test is: does it run in production?

**Practical application:** Design testing with this hierarchy. Local tests
catch obvious bugs fast. Staging tests catch integration issues. But only
production verification proves it works. Plan for all three levels — don't
stop at staging and call it done.

### Rule 3: Know your tests.

Different tests answer different questions. A load test won't tell you if
the login flow is correct. A unit test won't tell you if the system falls
over at 10,000 concurrent users. Use the right test for the right question.

**Practical application:** Before writing a test, ask: "What question am I
answering?" Then pick the test type that answers it. See Section 2 for the
full taxonomy.

### Rule 4: QA cleans up after itself.

All QA activity must be non-destructive and reversible. Snapshot state before
testing. Reverse all changes after. No leftover test data in databases, APIs,
or file systems. Log entries are the only acceptable permanent side effect.

**Practical application:** Every test suite has a teardown that reverses its
setup. Every QA campaign snapshots before and restores after. If you cannot
reverse an action, do not perform it during QA.

---

## 2. The Test Type Taxonomy

Not a hierarchy — a toolbox. Pick the right tool for the question.

| Type | What it proves | When to use | Cost | Speed |
|------|---------------|-------------|------|-------|
| **Static analysis** | Code is syntactically correct, types consistent | Every commit (linting, mypy) | Lowest | Fastest |
| **Unit** | Individual function works correctly | Every function with business logic | Low | Fast |
| **Integration** | Components work together | MCP tool calls, API endpoints, DB queries | Medium | Medium |
| **Contract** | API shape hasn't changed | Between services, schema regression | Medium | Fast |
| **E2E** | Full system delivers value | Critical user journeys | High | Slow |
| **Smoke** | System is alive and responsive | After deploy, before full test suite | Low | Fast |
| **Performance** | System meets speed/throughput targets | Lab + production measurement | High | Slow |
| **Load** | System handles expected traffic | Before releases, capacity planning | High | Slow |
| **Security** | System resists attacks | Every release, ongoing in production | High | Medium |
| **Chaos** | System recovers from failures | Infrastructure resilience testing | High | Varies |
| **Canary** | New version works in production | During gradual rollout | Medium | Ongoing |
| **Exploratory** | Edge cases machines miss | When automated tests all pass but doubt remains | Medium | Slow |

**Key insight:** Most teams over-index on unit tests and under-index on
integration and E2E. For MCP-first products, the integration layer IS the
product — MCP tool calls are the primary interface.

---

## 3. The Testing Trophy

The testing pyramid (lots of unit, some integration, few E2E) is being
replaced by the testing trophy, which better fits modern architectures
including MCP-first products.

```
    ╭───────╮
    │ E2E   │  ← Thin layer: critical user journeys only
    ╰───┬───╯
  ╭─────┴─────╮
  │Integration │  ← Largest layer: components working together
  ╰─────┬─────╯
 ╭──────┴──────╮
 │Static/Types  │  ← Widest base: linting, mypy, ruff
 ╰─────────────╯
```

**Why trophy over pyramid for our ecosystem:**
- MCP tools ARE the integration layer. Testing tool calls is integration
  testing, and it's where most bugs live.
- Unit tests are still valuable (catch regressions, localize failures) but
  they're not the largest investment.
- E2E tests are expensive but essential — a thin layer of critical journeys
  that prove the system delivers value.
- Static analysis (linting, type checking) is nearly free and catches entire
  categories of bugs before they exist.

---

## 4. Kano-Driven Test Depth

Reference `/kano-model` for the 10-level framework. Reference `/jj-qa`
Rule 5 for the minimum depth table.

**Translating Kano level into a concrete test plan:**

| Kano | Test plan |
|------|-----------|
| 1 (Security) | Unit + integration + E2E + security + chaos + penetration. Every use case, every corner case. Ongoing production security testing. |
| 2 (Core) | Unit + integration + E2E + performance. Every use case, 95% corner cases. |
| 3 (Auxiliary) | Unit + integration + E2E. Every use case, 75% corner cases. |
| 4 (Performance) | Lab measurement + production measurement. Performance regression detection. |
| 5 (Bells & Whistles) | Unit + integration. Every use case, 50% corner cases. |
| 6-10 | Unit. Every use case. Risk-based corners. |

**These are MINIMUMS (floors, not ceilings).** Mutation testing reveals
whether the floor is sufficient — surviving mutants mean you need more tests
regardless of the Kano minimum.

---

## 5. The BDD-to-Test Pipeline

Gherkin scenarios are the contract between PM and QA. Each scenario maps
directly to test code.

**The mapping:**
- **Given** → test setup / fixture
- **When** → call the function under test
- **Then** → assertions

**One scenario per behavior.** Each behavior maps to exactly one
Given/When/Then scenario — one testable assertion. If a behavior needs
multiple scenarios, split it into separate behaviors.

**The iris-qa model — three-layer hybrid test generation:**

1. **Layer 1: pytest-bdd (algorithmic, zero AI)** — Generates .feature files
   and test_*.py from BehaviorSpec. Step text classified by keywords, body
   generated algorithmically. 100% reproducible.

2. **Layer 2: Inspectors (algorithmic, zero AI)** — MCP inspector returns
   real tool names for step matching. Page inspector returns real CSS
   selectors. No guessing — real introspection.

3. **Layer 3: AI augmentation (Kano-driven)** — For Kano 1-3, AI writes
   assertion bodies for ambiguous Then steps. Kano 4-10: purely algorithmic.
   AI writes assert statements only, not test structure.

**Why this architecture:** Algorithmic test generation is 100% reproducible
and doesn't depend on LLM quality. AI is applied surgically where human
judgment is genuinely needed (assertion logic for complex behaviors), not as
a replacement for structured generation.

---

## 6. Four-Bucket Failure Triage

When a test fails, the failure is classified into exactly one bucket:

| Bucket | What's wrong | Who fixes it |
|--------|-------------|-------------|
| **target_bug** | Product code is wrong | Product worker |
| **spec_quality** | Gherkin is vague or incorrect | Product worker (PM) |
| **iris_qa_bug** | Test generator produced bad code | QA worker |
| **setup_data** | Test environment not in expected state | Orchestrator |

**Why this matters:** Without triage, the default response is "fix the test
to make it pass." But if the real problem is the product code, fixing the
test is hiding a bug. If the real problem is the spec, fixing the test is
encoding a wrong requirement. If the real problem is the environment, fixing
the test wastes time on a non-bug.

**LLM transients are retried, not triaged.** Flaky AI-generated assertions
get a retry before classification. Only persistent failures are triaged.

**spec_quality feedback loop:** When a test fails due to vague Gherkin, the
finding goes back to the PM for spec refinement. This is the iris-qa →
LeanSpecs feedback loop that improves specs through QA, not just tests.

---

## 7. Testing AI Agents and MCP Servers

AI agents and MCP servers introduce testing challenges that traditional QA
doesn't cover.

### Non-Deterministic Output

LLM outputs are probabilistic. The same input can produce different outputs.
Traditional pass/fail assertions don't work. Instead:
- **Statistical evaluation:** Run the same test N times, assert output is
  within acceptable range (semantic similarity, key content present)
- **Prompt regression suites:** Capture known-good outputs, detect drift
  when model or prompt changes
- **Confidence scoring:** Assert confidence is above threshold, not that
  output matches exact text

### Tool Schema Regression

The tool description and parameter schema are the LLM contract. If a
parameter name changes, every LLM consumer breaks. **Regression-test the
schema itself** — assert tool names, descriptions, and parameter shapes
haven't changed accidentally. Use `inline-snapshot` for complex structures.

### Tool Poisoning Defense

Attackers tamper with tool metadata to influence model behavior. Research
shows 72.8% attack success on capable models — they follow poisoned
instructions better because they're better at following instructions.

Defense:
- Review all tool descriptions before deployment
- Static analysis for hidden instructions in metadata
- Run `mcp-scan` (Invariant Labs) on all MCP servers
- Red-team tool descriptions: can you craft a description that makes the
  model do something unintended?

### LLM Chaos Input Testing

LLMs generate creative, malformed inputs. Every MCP tool needs adversarial
input tests: wrong types, empty strings, huge payloads, injection attempts
(`; rm -rf`, SQL injection, path traversal), missing required fields, extra
unexpected fields, Unicode edge cases.

### Multi-Agent Pipeline Testing

When agents chain actions across services, a bad output from agent A becomes
input to agent B. By the time a human sees the error, it's three steps deep.
Test chain effects, not just individual agent behavior. Mock upstream agents
with known-bad outputs to verify downstream resilience.

### Confused Deputy

MCP servers often run with elevated privileges. Test that tools enforce
user-scoped access. If tool A deletes a record, can it only delete records
belonging to the requesting user? Are server-level credentials exposed?

### AI-Generated Code QA

Research shows 50%+ of AI-generated code contains logical or security flaws.
Hallucinated API calls, security anti-patterns, business logic guesses.
**Never trust AI-generated code without review.** Apply the same coding DNA
standards. Run mutation testing against AI-generated tests.

---

## 8. Production QA — Shift-Right

"I don't care if it runs in staging. I only care if it runs in production."

### Canary Deployment

Gradual rollout to a subset of users/servers with real-time monitoring.
Predefined rollback criteria:
- Error rate > X% → automatic rollback
- Response latency > Y ms → automatic rollback
- Business metric degradation → alert + manual decision

### Post-Deploy Verification

After every deployment:
1. **Health check** — is the service alive and responding?
2. **Smoke test** — does the critical path work?
3. **Canary period** — monitor error rates, latency, business metrics
4. **Full verification** — only after canary period passes

### Production Observability

Monitor continuously, not just at deploy time:
- Error rates and error types
- Latency percentiles (p50, p95, p99)
- Business metrics (conversion, engagement, task completion)
- Structured logs for debugging without reproducing locally

### Chaos Engineering

Deliberate failure injection to test resilience:
- Kill a container — does the system recover?
- Introduce network latency — does it degrade gracefully?
- Exhaust a resource (memory, disk) — does it alert before crashing?

### The Continuous Quality Loop

Shift-left (design-time quality) + shift-right (production verification)
form a continuous loop:
```
Spec → Test Generation → Unit/Integration → E2E → Deploy →
Canary → Production Monitoring → Findings → Spec updates → ...
```

---

## 9. Regression Gates and Release Decisions

### LAUNCH / HALT — Binary Gate

Two outcomes only. No intermediate "DEGRADED" state. Partial quality is a
lie — it means "we know it's broken but we're shipping anyway."

- **LAUNCH:** All test categories above threshold
- **HALT:** Any test category below critical threshold

### Regression-Locked Tests

Once a test passes, it enters `regression_locked` state. New code cannot
break regression-locked tests. This prevents silent quality degradation —
the test suite only gets stronger over time.

### Grading Thresholds

| Grade | Pass Rate | Meaning |
|-------|-----------|---------|
| Excellent | ≥ 90% | Ship with confidence |
| Good | ≥ 75% | Ship with monitoring |
| Degraded | ≥ 50% | Do not ship — fix first |
| Critical | < 50% | HALT — fundamental problems |

### Dual-Axis Categorization

Every test is classified on two axes:
- **test_target:** api, ui, security, performance, database, etc.
- **test_scope:** functional, smoke, integration, regression, e2e, etc.

This enables per-target, per-scope grading. A product can LAUNCH with
"api/functional: Excellent" and "ui/accessibility: Good" but HALT on
"security/regression: Critical."

---

## 10. The Heal Framework — Self-Healing QA Infrastructure

Reference `/heal` for the full framework.

**Core principles:**
- **All diagnostics go INTO the framework.** Don't run ad-hoc terminal
  commands. Add diagnostic checks to `test_<component>.py`, re-run heal.py.
- **All fixes go INTO the framework.** Don't run one-off fixes. Add heal
  steps so heal.py fixes it automatically next time.
- **Binary-search fault isolation.** For N components, find the fault in
  O(log N) tests, not O(N).
- **E2E first.** If the E2E test passes, no component tests needed. Only
  drill down on failure.
- **Rebuilds are valid.** `docker compose build <service>` is a legitimate
  heal action. Don't shy away from it.

---

## 11. QA Self-Interrogation Checklist

Before declaring QA "done" for a product or release:

1. Does test depth meet the Kano floor for every behavior?
2. Is E2E covering critical user journeys (not just unit tests)?
3. Are failures triaged into the four buckets (not just "test failed")?
4. Is the mutation score above 70%?
5. Do tests run in production (canary, health checks)?
6. Are regression-locked tests protected from breakage?
7. Is QA cleaning up after itself (no leftover test data)?
8. For MCP tools: schema regression, chaos inputs, privilege boundaries?
9. For AI outputs: statistical evaluation, prompt regression, drift monitoring?
10. Would the heal framework fix this problem automatically next time?
