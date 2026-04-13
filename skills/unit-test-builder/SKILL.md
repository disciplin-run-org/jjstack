---
name: unit-test-builder
description: >
  Generate TDD test suites using adversarial thinking and systematic test design.
  Language-agnostic strategy: boundary analysis, equivalence partitioning, mutation
  testing, property-based testing. Tests first, implementation second. For
  Python/pytest-specific mechanics, see /python-coder. Trigger on: "write tests",
  "add test coverage", "TDD", "unit tests for", "test this module", "create test
  suite", or before implementing a new module.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
  - Agent
---

# Unit Test Builder — jjstack Skill

Generate TDD test suites grounded in adversarial thinking and systematic test
design. Tests first, implementation second. Philosophy first, mechanics second.

## When to Use

Invoke `/unit-test-builder` when:
- Starting a new module and need tests written before implementation
- Adding test coverage for existing code
- Reviewing whether a test suite is thorough enough
- Running mutation testing to find blind spots

## Mandatory Pre-Steps

1. **Load the testing philosophy:**

```bash
cat ~/.claude/skills/jjstack/references/unit-test-philosophy.md
```

2. **Read the coding DNA:** `cat ~/.claude/skills/jjstack/jjstack.config.yaml`
   then read the `dna.coding` file.

3. **Read any LeanSpecs Gherkin** for the module if available (each test should
   trace to a behavior ID).

4. **Read any existing `conftest.py`** to avoid duplicating fixtures.

5. **Read `pyproject.toml`** to understand the project's test framework and
   dependencies.

## Test Strategy Workflow

After loading the philosophy, apply this workflow for every module:

### Step 1: Identify Kano Level

What Kano level is this feature? Use `/kano-model` to determine minimum test
depth. Remember: Kano depths are FLOORS, not ceilings.

### Step 2: Map BDD to Tests

Each Gherkin scenario → at least one test:
- **Given** → test setup / fixture
- **When** → call the function under test
- **Then** → assertions

### Step 3: Apply Adversarial Thinking

For every function, ask:
1. What inputs did I NOT think about when writing this?
2. What state can the caller be in that I assumed they wouldn't be?
3. What happens when a dependency returns something unexpected?

### Step 4: Systematic Test Case Design

- **Equivalence partitioning** — divide input space into classes, one test
  per class
- **Boundary value analysis** — test at edges (min-1, min, min+1, max-1,
  max, max+1, empty, None)
- **Decision tables** — enumerate boolean condition combinations
- **State transitions** — test every valid AND invalid state change

### Step 5: Write Negative Tests

Test what should NOT happen. Invalid inputs, wrong states, missing fields,
injection attempts. The negative tests are where bugs live.

### Step 6: Test Error Messages

Assert specific text in error messages, not just that errors occur. Especially
critical for MCP tools where vague errors cause LLM retry loops.

### Step 7: Verify with Mutation Testing

After writing tests, run mutation testing to find surviving mutants. Each
survivor is a blind spot. The loop:
```
Write tests → run mutation testing → kill survivors →
add property-based tests → re-run → iterate
```

## Test File Structure (Python Example)

```python
"""Tests for {module} — {description}.

Driven by LeanSpecs Gherkin:
- {behavior_id}: {summary}
"""

# Standard Libraries
...

# 3rd party
import pytest
from pydantic import ValidationError

# Local
from {package}.{module} import ...


######################################################################
# {Section Name} Tests
######################################################################


class Test{ModelOrFunction}:
    """{LeanSpecs reference and Gherkin scenario}."""

    def test_{happy_path}(self) -> None:
        ...
        return

    def test_{boundary_case}(self) -> None:
        ...
        return

    def test_{invalid_input_rejected}(self) -> None:
        with pytest.raises(ValidationError) as exc_info:
            ...
        #end with
        assert "{field}" in str(exc_info.value)
        return
```

For Python/pytest-specific patterns (fixtures, parametrize, Hypothesis,
mutmut, conftest), see `/python-coder`.

## Self-Review Checklist

Before delivering tests, apply the self-interrogation checklist from the
philosophy reference:

1. Every test traces to a BDD scenario, requirement, or documented risk
2. Boundaries tested (not just happy-path midpoints)
3. Negative cases tested (invalid input, missing data, wrong state)
4. No test depends on another test's side effects
5. Mocks only at system boundaries
6. No tautological tests (tests define behavior, not mirror implementation)
7. Test names describe the requirement, not the method being called
8. Kano-appropriate depth met or exceeded
9. Error messages assert specific text, not just error type
10. For MCP tools: schema stability and chaos input tested
11. Mutation testing considered — surviving mutants reviewed
