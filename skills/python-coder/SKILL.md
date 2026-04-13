---
name: python-coder
description: >
  Use this skill whenever writing, editing, refactoring, reviewing, or testing Python code.
  Trigger on any request involving Python files (.py), Python project setup, pytest, or Python
  tooling configuration (pyproject.toml, setup.cfg, setup.py, .flake8, .pre-commit-config.yaml
  when it configures Python tools). Also trigger when creating new Python projects, adding
  Python dependencies, or writing Python-related CI/CD steps. Do NOT trigger for pure YAML,
  Markdown, Dockerfiles, shell scripts, or other non-Python files unless they are Python
  tooling configuration.
---

# Python Coder — Coding DNA

## MANDATORY: Read the Coding DNA before writing a single line

**Step 1 — Load Coding DNA from jjstack config:**

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

Read the `dna.coding` path from the config and read that file in full. This is the
complete specification of how code should be written — structure, naming, error handling,
philosophy, and anti-patterns. It is not optional and must not be skimmed. Every line of
Python you produce must match the coding DNA — not generic AI output.

A default coding DNA ships with jjstack at `references/coding-dna.md`. Users can
override it with their own by changing `dna.coding` in `jjstack.config.yaml`.

If the DNA file is not found, use the Quick-Reference Card below as the baseline standard.

---

## Quick-Reference Card — Top 20 Rules

Keep these in working memory as a checklist while writing code:

### Structure
1. **Top-down declaration order.** Functions defined before called. Helpers above callers. `main()` last.
2. **`if __name__ == "__main__":` guard** at the end of every script.
3. **Copyright header** on every file (if the project uses one).
4. **ASCII separator blocks** (`######`) between major sections.
5. **Functions ~30-50 lines max.** If longer, extract a helper.
6. **Max 3 levels of indentation** inside a function. Extract or invert if deeper.

### Imports
7. **Three groups with section comments:** `# Standard Libraries` / `# 3rd party` / `# Local`.
8. **`from X import *`** only for local config modules (`localsettings.py`). Nowhere else.

### Naming
9. **snake_case** for everything. No exceptions.
10. **Domain-specific names.** Never `data`, `result`, `temp`, `val`, `x`, `items`, `output`, `response`.
11. **`unused_` prefix** for tuple elements you do not need.

### Functions & Types
12. **Type hints** in all function signatures.
13. **Google-style docstrings** on public functions. No docstrings on private helpers.
14. **Explicit `return`** at end of every function, even void (`return` or `return None`).
15. **Tuple unpacking** with parentheses: `(port, protocol) = (vuln["port"], vuln["protocol"])`.

### Block-End Comments
16. **`#end if`, `#end for`, `#end while`, `#end try`, `#end with`** on every significant block.

### Error Handling
17. **Validate before you try.** Check conditions, do not catch crashes.
18. **Specific exceptions first**, then catch-all `Exception`. Never bare `except:`.
19. **Never swallow errors silently.** Callers must distinguish success from failure.

### Anti-AI Tells — Purge These
20. **Zero emoji** in code, comments, or docstrings. **No walrus operator (`:=`).** No `if flag == True:` or `if len(items) == 0:` — use truthiness. No "Let's" or "we" in comments. No tutorial-style comments. No `Optional[X]` — use `X | None`.

---

## Project Setup (new projects only)

### pyproject.toml is mandatory

Every Python project must have a `pyproject.toml`. It is the single source of
truth for project metadata, dependencies, and tool configuration. Usually created
by `uv init`, but if you don't use uv then create one anyway.

### UV — Preferred Python Tooling

Use `uv` instead of `pip`, `pip-tools`, `venv`, and `pip install` wherever possible:

- **New projects:** `uv init` instead of manual `pyproject.toml` + `venv`
- **Virtual environments:** `uv venv` instead of `python -m venv`
- **Installing deps:** `uv pip install` instead of `pip install`
- **Adding deps:** `uv add <package>` instead of manually editing `pyproject.toml`
- **Running scripts:** `uv run <script.py>` instead of activating a venv first
- **Locking deps:** `uv lock` instead of `pip-compile`

When modifying existing projects that already use `pip` + `requirements.txt`, do not
force-migrate to `uv` unless asked. But for new projects and fresh environments,
default to `uv`.

---

## Testing — Python/pytest Mechanics

For test STRATEGY and PHILOSOPHY (what to test, adversarial thinking, boundary
analysis, mutation testing), use `/unit-test-builder`. This section covers
pytest-specific MECHANICS that implement the philosophy.

### Pattern 1: Pydantic Model Validation Testing

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

### Pattern 2: Fixture Factory (conftest.py)

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

### Pattern 3: Workspace Fixture

For modules that read/write files:

```python
@pytest.fixture
def workspace_dir(tmp_path: Path) -> Path:
    """Temporary workspace with standard directory layout."""
    specs_dir = tmp_path / "specs"
    specs_dir.mkdir()
    (tmp_path / "tests" / "generated").mkdir(parents=True)
    (tmp_path / "tests" / "custom").mkdir(parents=True)
    (tmp_path / "results").mkdir(parents=True)
    return tmp_path
```

### Pattern 4: Enum Completeness

Always test enum member count to catch accidental additions/removals:

```python
def test_only_two_values(self) -> None:
    assert len(ReleaseStatus) == 2
    return
```

### Pattern 5: FastMCP Tool Testing

Test tool functions directly using FastMCP's in-memory client:

```python
@pytest.fixture
async def mcp_client():
    """In-memory FastMCP client for tool testing."""
    from fastmcp import Client
    from my_package.mcp_server import mcp

    async with Client(mcp) as client:
        yield client
    #end async with

@pytest.mark.asyncio
async def test_tool_returns_expected(mcp_client) -> None:
    result = await mcp_client.call_tool("my_tool", {"param": "value"})
    assert result[0].text  # verify non-empty response
    return
```

For `@mcp.tool(task=True)` async tools, test the underlying function directly
(bypassing the task wrapper) since FastMCP task lifecycle is tested by FastMCP.

### Pattern 6: Async Task Testing

```python
@pytest.mark.asyncio
async def test_async_tool_returns_scorecard() -> None:
    """Test the async tool function directly."""
    result = await my_async_tool(workspace="test", scope="smoke")
    assert result["status"] in ("success", "error")
    return
```

Configure pytest-asyncio in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

### Pattern 7: pytest Marker Convention

Tests trace to LeanSpecs behaviors via docstrings when available:

```python
def test_launch_status(self) -> None:
    """LeanSpecs 4.5.1: LAUNCH when all categories pass."""
    ...
```

### Pattern 8: Subprocess Mock

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

### Pattern 9: Parametrize for Boundary Coverage

Use `@pytest.mark.parametrize` to implement boundary value analysis from the
philosophy without writing N separate test functions:

```python
@pytest.mark.parametrize("age,should_pass", [
    (-1, False),   # below min boundary
    (0, True),     # min boundary
    (1, True),     # min+1
    (149, True),   # max-1
    (150, True),   # max boundary
    (151, False),  # above max boundary
])
def test_age_validation(self, age: int, should_pass: bool) -> None:
    """Boundary value analysis for age field."""
    if should_pass:
        person = Person(age=age)
        assert person.age == age
    else:
        with pytest.raises(ValidationError):
            Person(age=age)
        #end with
    #end if
    return
```

### Pattern 10: conftest Hierarchy

conftest.py files compose. Use the hierarchy:
- **Root conftest** (`tests/conftest.py`) — shared fixtures (sample models, temp dirs, mock servers)
- **Package conftest** (`tests/unit/conftest.py`) — domain-specific fixtures
- Import inside fixture body to avoid circular imports and load-order issues

### Pattern 11: Hypothesis Property-Based Testing

Define invariants, let Hypothesis find counterexamples. Each property test
kills ~50x more mutants than a hand-written test.

```python
from hypothesis import given, settings
from hypothesis import strategies as st

@given(name=st.text(min_size=1, max_size=200))
@settings(max_examples=200)
def test_spec_roundtrip(self, name: str) -> None:
    """Any valid name survives JSON round-trip."""
    spec = Spec(name=name)
    json_str = spec.model_dump_json()
    restored = Spec.model_validate_json(json_str)
    assert restored.name == name
    return
```

Good properties to test:
- **Round-trip**: `deserialize(serialize(x)) == x`
- **Idempotency**: `f(f(x)) == f(x)`
- **Invariants**: `len(filter(items)) <= len(items)`
- **Oracle**: compare against a simple reference implementation

Add `hypothesis` to dev dependencies:

```toml
[project.optional-dependencies]
dev = ["hypothesis", ...]
```

### Pattern 12: mutmut Mutation Testing

Run after writing tests to find blind spots. Surviving mutants = tests you
need to write or assertions you need to tighten.

**Setup in `pyproject.toml`:**

```toml
[tool.mutmut]
paths_to_mutate = ["src/"]
tests_dir = "tests/"
runner = "python -m pytest -x --tb=no -q"
mutate_only_covered_lines = true
```

**The survivor workflow:**

```bash
mutmut run                    # mutate source, run tests
mutmut browse                 # interactive view of survivors
mutmut show <id>              # inspect a specific survivor
```

Each surviving mutant is one of:
- **Real blind spot** → write a targeted test to kill it
- **False positive** → logger/metrics code you deliberately don't test
- **Equivalent mutant** → mutation that doesn't change observable behavior

Use mypy/pyrefly to automatically filter type-invalid mutants. Target 70%+
mutation score to start, iterate toward 85%.

Add `mutmut` to dev dependencies:

```toml
[project.optional-dependencies]
dev = ["mutmut", ...]
```

---

## Self-Review Checklist — Run Before Delivering Code

Before presenting any Python code, verify all 12 items:

1. Every significant `if`/`for`/`while`/`try`/`with` block has its `#end` comment
2. Imports are grouped with `# Standard Libraries` / `# 3rd party` / `# Local` comments
3. Functions are declared top-down (helpers above callers, `main()` last)
4. Copyright header is present (if project uses one)
5. No walrus operator (`:=`) anywhere
6. No emoji anywhere — comments, docstrings, strings
7. No generic variable names (`data`, `result`, `temp`, `val`, `items`)
8. All function signatures have type hints
9. All functions end with explicit `return`
10. f-strings used (not `%` or `.format()`)
11. `pathlib.Path` used (not `os.path`)
12. No "Let's", "we", or tutorial-style comments
13. Test philosophy applied — see `/unit-test-builder` for strategy checklist
14. pytest patterns from this skill applied (fixtures, parametrize, conftest, Hypothesis)
