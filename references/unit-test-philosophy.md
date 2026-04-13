# Unit Test Philosophy — Testing Your Own Code Honestly

How to write unit tests that actually catch bugs, not just prove your code
runs. The hard part isn't pytest mechanics — it's fighting your own blind
spots. This document is language-agnostic. For Python/pytest patterns, see
`/python-coder`.

---

## 1. The Hard Problem

You wrote the code. Your tests will follow the same mental model unless you
actively fight it. The goal is adversarial honesty.

**Author's blind spots:**
- **Happy path bias** — you test the paths you coded for
- **Assumption leak** — you skip inputs you "know" won't happen
- **Coupling trap** — you test implementation details because you know them
- **Tautological tests** — tests that pass by construction (assert what the
  code literally does, proving nothing)

**The adversarial stance — three questions for every function:**
1. What inputs did I NOT think about when writing this?
2. What state can the caller be in that I assumed they wouldn't be?
3. What happens when a dependency returns something unexpected?

If you can't answer these, you haven't tested enough.

---

## 2. Test Case Design — Systematic, Not Intuitive

### Equivalence Partitioning

Divide the input space into classes where behavior should be identical. One
test per class. If `age` accepts 0-150:
- Valid: {0, 75, 150}
- Negative: {-1}
- Overflow: {151}
- Wrong type: {"old"}

### Boundary Value Analysis

Test at edges, not midpoints. Off-by-one is the most common bug class.

For any range or constraint, test: **min-1, min, min+1, max-1, max, max+1**.

Universal boundaries to always consider:
- Zero, one, two (empty, single, pair)
- Empty string, empty list, empty dict
- None / null
- Max int, max string length
- Negative values where positive expected
- Unicode, special characters, whitespace-only

### Decision Tables

When a function has multiple boolean conditions, enumerate combinations.
N booleans = 2^N cases. For >4 conditions, use pairwise coverage (every
pair of values appears in at least one test case).

### State Transition Testing

When an object has lifecycle states (draft → active → archived), test:
- Every valid transition (draft → active)
- Every invalid transition (archived → draft)
- The invalid transitions are where bugs hide

---

## 3. What to Test

### The Pager Heuristic

"If this breaks, does someone get paged?" If yes: test it. Business logic
always qualifies. Glue code sometimes. Formatting rarely.

### Kano-Driven Depth

Reference `/kano-model` — Kano level sets the FLOOR for test investment:

| Kano 1-2 (Security/Core) | Every use case + every corner case |
| Kano 3 (Auxiliary) | Every use case + 75% corners |
| Kano 4 (Performance) | Lab + production measurement |
| Kano 5+ (B&W, Me Too, etc.) | Every use case + risk-based corners |

These are minimums. Always strive higher.

### BDD-to-Test Pipeline

Gherkin scenarios (Layer 7) map directly to test structure:
- **Given** → test setup / fixture
- **When** → call the function under test
- **Then** → assertions

Each Gherkin scenario produces AT LEAST one test. Complex scenarios with
multiple Then clauses may produce multiple tests (one assertion concern
per test).

---

## 4. What NOT to Test

**Test behavior, not implementation.** Test WHAT the function returns/does,
not HOW it does it internally. If you refactor internals and tests break,
the tests were coupled to implementation.

**Do not test the language or framework.** Don't test that dict lookup works,
that Pydantic validates types, that pytest.raises catches exceptions. Test
YOUR logic that uses these tools.

**Do not test private internals directly.** If a helper is only called by one
public function, test through the public function. Extract to its own module
only if it genuinely needs its own tests.

**The maintenance cost test.** Every test is code you maintain. Before writing
a test, ask: "Will this test still be valid after the next refactor?" If the
answer is "only if I don't change the implementation," the test is too coupled.

**E2E testing is covered elsewhere.** This document focuses on unit tests.
E2E tests prove the system works. Unit tests prove the parts work and catch
regressions. Both matter; don't confuse them.

---

## 5. Test Independence

No test depends on another test. No shared mutable state between tests.
Each test creates its own world, runs, and tears it down.

- Tests must pass in any order (random ordering must not break you)
- No global variables modified by tests
- Fixtures that return mutable objects must create fresh instances
- Database tests use transactions that roll back, or isolated temp schemas
- File-system tests use temp directories, never shared paths

---

## 6. Error Message Quality

Not just "raises error" but "error message helps the caller fix the problem."

**Assert specific text in error messages**, not just that an error occurred.
A test that only checks `pytest.raises(ValueError)` misses the case where
the function raises ValueError for the wrong reason.

**Why this matters for MCP tools:** When an LLM gets a vague error from a
tool, it retries with equally wrong parameters — forever. Precise error
messages ("parameter 'repo' must be a non-empty string, got empty string")
let the LLM self-correct. Test that your errors contain the field name,
the bad value, and what was expected.

---

## 7. MCP-Specific Testing

MCP servers have unique testing traps beyond normal application code.

### Tool Schema Regression

The tool description and parameter schema are the LLM contract. If a
parameter name changes or a description becomes ambiguous, every LLM
consumer breaks. **Regression-test the schema itself** — assert tool names,
descriptions, and parameter shapes haven't changed accidentally.

### LLM Chaos Input Testing

LLMs generate creative, malformed, and unexpected inputs. Every tool needs
adversarial input tests:
- Wrong types (string where int expected, list where string expected)
- Empty strings, None, huge payloads
- Injection attempts (`; rm -rf`, `$(curl ...)`, SQL injection strings)
- Missing required fields, extra unexpected fields
- Unicode edge cases, control characters

### Confused Deputy / Privilege Boundary

MCP servers often run with elevated privileges. Test that tools enforce
user-scoped access:
- If tool A deletes a record, can it only delete records belonging to the
  requesting user?
- Can a crafted request access resources outside the user's scope?
- Are server-level credentials exposed through tool responses?

### Command Injection via Tool Parameters

Tool parameters may be passed to functions that execute commands, build
queries, or construct file paths. Test with adversarial inputs that attempt
path traversal (`../../etc/passwd`), command injection (`; cat /etc/shadow`),
and template injection.

---

## 8. Testing Your Tests

Writing tests isn't enough. You need to verify that your tests actually
catch bugs. Two complementary techniques:

### Mutation Testing

Systematically mutate your source code (change `+` to `-`, `True` to `False`,
`>=` to `>`, remove function calls) and re-run your test suite. If all tests
still pass after a mutation, that's a **surviving mutant** — proof your tests
have a blind spot.

Mutation testing answers: "Would my test suite catch this bug?"

Run after writing tests, not instead of thinking about what to test. It
reveals gaps, but you still need the adversarial mindset to write meaningful
tests in the first place.

### Property-Based Testing

Instead of testing specific inputs, define *properties* (invariants) that
must hold for ALL inputs. The framework generates hundreds of cases including
edge cases you'd never think of.

Research shows each property-based test kills ~50x more mutants than a
traditional hand-written unit test (OOPSLA 2025). This makes it the single
highest-leverage technique for test quality.

Good properties to test:
- Round-trip: `deserialize(serialize(x)) == x`
- Idempotency: `f(f(x)) == f(x)`
- Invariants: `len(filter(items)) <= len(items)`
- Commutativity: `merge(a, b) == merge(b, a)` (when applicable)
- Oracle: compare against a simple reference implementation

### The Combined Loop

```
Write tests → run mutation testing → kill survivors →
add property-based tests for broad coverage → re-run →
iterate until score target met (70%+ to start)
```

Each surviving mutant is either:
- A real blind spot → write a targeted test to kill it
- A false positive → logger/metrics code you deliberately don't test
- An equivalent mutant → mutation that doesn't change behavior

Review each survivor. Don't chase 100% — diminishing returns past ~85%.

---

## 9. Test Smells

| Smell | Symptom | Fix |
|-------|---------|-----|
| **Tautological** | Asserts what the code literally does | Test the requirement, not the implementation |
| **Over-mocking** | More mock setup than test logic | Mock at boundaries only, never mock the SUT |
| **Brittle** | Breaks on every refactor | Test behavior/output, not internal structure |
| **Mystery guest** | Depends on external file/DB/env state | Use fixtures, inline test data |
| **Eager test** | One test checks many unrelated things | Split into focused tests |
| **Slow test** | >1s for a unit test | Mock I/O, use in-memory alternatives |
| **Copy-paste** | 5 tests differ by one parameter | Use parametrize |
| **Liar test** | Test name says X, assertions check Y | Name must match what is verified |
| **Second-class test** | Test code exempt from quality standards | Same DNA rules as production code |

---

## 10. Self-Interrogation Checklist

Before declaring a test suite "done":

1. Did I test what should NOT happen (not just what should)?
2. Did I test boundaries, not just happy midpoints?
3. Would a developer who never saw my code understand what each test verifies?
4. If I delete the implementation, do the tests still define correct behavior?
5. Are my mocks at system boundaries, not deep in my own code?
6. Does every test trace to a requirement or known risk?
7. Can I run tests in random order without failures?
8. Did I consider: empty, null, negative, overflow, duplicate, concurrent?
9. Would surviving mutants reveal blind spots in my assertions?
10. For MCP tools: did I test error message precision and schema stability?
