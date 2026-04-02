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
