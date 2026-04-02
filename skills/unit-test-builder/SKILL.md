---
name: unit-test-builder
description: >
  Generate TDD test suites for Python projects. Tests first, implementation second.
  Trigger on: "write tests", "add test coverage", "TDD", "unit tests for",
  "test this module", "create test suite", or before implementing a new module.
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

Generate TDD test suites for Python projects following the jjstack coding DNA.
Tests first, implementation second.

## When to Use

Invoke `/unit-test-builder` when:
- Starting a new module and need tests written before implementation
- Adding test coverage for existing Pydantic models, FastMCP tools, or async tasks
- Need fixture factories or conftest patterns for a test suite

## Mandatory Pre-Steps

1. Read the coding DNA: `cat ~/.claude/skills/jjstack/jjstack.config.yaml` then read the `dna.coding` file.
2. Read any LeanSpecs Gherkin for the module if available (each test should trace to a behavior ID).
3. Read any existing `conftest.py` to avoid duplicating fixtures.
4. Read `pyproject.toml` to understand the project's test framework and dependencies.

## Test File Structure

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

    def test_{validation_error}(self) -> None:
        with pytest.raises(ValidationError) as exc_info:
            ...
        #end with
        assert "{field}" in str(exc_info.value)
        return

    def test_{json_round_trip}(self) -> None:
        json_str = model_instance.model_dump_json()
        restored = ModelClass.model_validate_json(json_str)
        assert restored == model_instance
        return
```

## Pattern Catalog

### 1. Pydantic Model Validation Testing

Test every model with:
- **Happy path**: valid construction, field access
- **Required field missing**: `pytest.raises(ValidationError)`, check field name in error
- **Field constraints**: `ge=`, `le=`, `pattern=` — test boundary values
- **Defaults**: verify `None` defaults, `False` defaults, empty list defaults
- **JSON round-trip**: `model_dump_json()` -> `model_validate_json()` -> assert equality
- **Enum constraints**: verify exact values AND count (`len(MyEnum) == N`)

```python
def test_kano_level_must_be_positive(self) -> None:
    with pytest.raises(ValidationError):
        BehaviorSpec(
            behavior_id="1.1.1",
            summary="Invalid kano",
            kano_level=0,  # Field(ge=1) should reject
            ...
        )
    #end with
    return
```

### 2. Fixture Factory Pattern (conftest.py)

Each model gets a `sample_{model_name}` fixture returning a populated instance.
Fixtures compose: `sample_run_report` depends on `sample_scorecard` and `sample_test_result`.

```python
@pytest.fixture
def sample_behavior_spec():
    """A representative approved BehaviorSpec for testing."""
    from iris_qa.models import BehaviorSpec

    return BehaviorSpec(
        behavior_id="3.3.1",
        summary="Builds BehaviorSpec list",
        ...
    )
```

Import inside the fixture body to avoid import errors when conftest loads before
the package is installed.

### 3. Workspace Fixture Pattern

For modules that read/write files (spec_loader, test_runner, scorecard):

```python
@pytest.fixture
def workspace_dir(tmp_path: Path) -> Path:
    """Temporary workspace with standard iris-qa directory layout."""
    specs_dir = tmp_path / "specs"
    specs_dir.mkdir()
    (tmp_path / "tests" / "generated").mkdir(parents=True)
    (tmp_path / "tests" / "custom").mkdir(parents=True)
    (tmp_path / "results").mkdir(parents=True)
    return tmp_path
```

### 4. Enum Completeness Testing

Always test enum member count to catch accidental additions/removals:

```python
def test_only_two_values(self) -> None:
    assert len(ReleaseStatus) == 2
    return
```

### 5. FastMCP Tool Testing (Phase 3+)

Mock the FastMCP server, test tool functions directly:

```python
@pytest.fixture
def mcp_server():
    """FastMCP server instance for tool testing."""
    from fastmcp import FastMCP
    mcp = FastMCP("{server-name}-test")
    # Register tools on the test server
    from {package}.mcp_server import register_tools
    register_tools(mcp)
    return mcp
```

For `@mcp.tool(task=True)` async tools, test the underlying function directly
(bypassing the task wrapper) since FastMCP task lifecycle is tested by FastMCP itself.

### 6. Async Task Testing (Phase 3+)

```python
@pytest.mark.asyncio
async def test_iris_qa_run_returns_scorecard() -> None:
    """Test the async tool function directly."""
    result = await my_async_tool(workspace="test", scope="smoke")
    assert result["status"] in ("success", "error")
    return
```

### 7. pytest Marker Convention

Tests trace to LeanSpecs behaviors via docstrings when available:

```python
def test_launch_status(self) -> None:
    """LeanSpecs 4.5.1: LAUNCH when all categories pass."""
    ...
```

### 8. Subprocess Mock Pattern (Phase 4: test_runner)

```python
@pytest.fixture
def mock_pytest_subprocess(mocker):
    """Mock subprocess.run for pytest invocation."""
    mock_run = mocker.patch("{package}.test_runner.subprocess.run")
    mock_run.return_value = mocker.Mock(
        returncode=0,
        stdout='{"tests": [...]}',
    )
    return mock_run
```

## Self-Review Checklist

Before delivering tests:
1. Every test has explicit `return` at the end
2. `#end with` / `#end for` on significant blocks
3. Imports grouped: Standard Libraries / 3rd party / Local
4. ASCII section separators between test classes
5. No generic variable names (`data`, `result`, `items`)
6. Each test class has a docstring citing LeanSpecs behavior ID
7. JSON round-trip test for every Pydantic model
8. Validation error tests check field name in error message
9. No mocking of internal code — only mock at boundaries
10. Fixtures compose (use other fixtures, not duplicate setup)
