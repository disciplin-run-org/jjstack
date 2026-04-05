# jjstack Coding DNA

*Based on the coding philosophy of Jesper Jurcenoks. Opinionated by design.*

## 1. Where This Philosophy Comes From

This coding DNA originated with a developer who started coding before OOP existed. Read Stroustrup's original C++ books when they came out. Learned Yourdon's data modeling with data flow diagrams in 1986 - still uses it. Decades in cybersecurity building vulnerability scanners, threat intelligence platforms, and security assessment tools.

The philosophy reflects that background: minimalism, pragmatism, security-first thinking. Functions over classes. Data models over frameworks. Cost efficiency over elegance theater. Code that runs on the oldest hardware at the lowest cost in the industry.

Three words: builder, reductionist, reframer.

## 2. Core Philosophy

Data model is king. Before writing a line of code, define the data: what comes in, what goes out, how it flows. Yourdon's data flow diagrams from 1986 are still the goto. Everything else follows from getting the data model right.

Lowest cost of execution. An extra index is never as good as fixing the query. Fewer CPU cycles, less data transfer, fewer AI tokens. This is not optimization theater - it is a design constraint applied from line one.

Primitives over frameworks. If the standard library solves it, use the standard library. A framework is debt with interest. A primitive is paid in full. When the stdlib has a clean solution - `dataclasses` for fixed schemas, `collections.defaultdict` for grouped data, `itertools` for iteration patterns - use it instead of hand-rolling the equivalent.

Retain option-value. Play the long game. If refactoring is coming down the road, design for it now. Placeholders and comments that signal future modules are cheap insurance. Pay a little extra today to keep options open tomorrow.

Readability is paramount. Code is read ten times for every one time it is written. If the reader cannot follow it, it does not matter how clever it is.

Compression is the editorial principle. No waste. Every line earns its place. Compression serves clarity - never obscures it.

Quality, Quantity, Efficiency - deliver all three, always.

For anything not explicitly covered in this document, enforce industry best practice. PEP 8 is the baseline. When drawing inspiration from Stack Overflow, GitHub, or any external source, never use the code as-is. Refactor to best practice first - fix naming, error handling, type hints, security, and structure before it touches the codebase. External code is a starting point, not a solution.

## 3. Problem Decomposition

First move: find the data model. Define inputs, outputs, and the transformations between them. The data flow diagram is the design.

Second move: The Reduction. Collapse the problem into its simplest form. SQL injection, XSS, CSRF all collapse into "misplaced trust." Find the hidden variable that everything aligns around. The simpler model is almost always the more accurate model.

Third move: reframe before solving. "Nobody cares about backups - people only care about restores." Do not attack the problem as stated. Find the angle that makes the solution obvious.

Function decomposition follows naturally: each function is one transformation in the data flow. If a function does two things, it is two functions. If a function is longer than one screen (~30-50 lines), break it up.

Design for lowest cost of execution from the start. Do not load more data than needed. Do not make API calls you can avoid. Do not loop twice when once will do.

## 4. Architecture & Tradeoffs

OOP in moderation. Classes exist to hold state that genuinely needs to travel together. If a module-level dictionary and three functions solve the problem, that is the right answer. Class hierarchies are a cost - justify every level.

The test: does this class make the code easier to read and reason about? If the answer is "it follows the pattern" instead of "yes," delete the class.

Long-game architecture. Think ahead, build for now. Placeholders and comments for future modules cost nothing. Over-abstraction for hypothetical requirements costs everything. The difference: option-value is a comment that says `# Phase 2: webhook support goes here.` Over-engineering is an abstract WebhookStrategyFactory that nobody asked for.

Module structure reads like a book. Top-down declaration order. Functions defined before they are called. Helper functions above the functions that use them. `main()` at the bottom. The reader should never have to scroll up to understand what they are reading. C heritage - and still the right call.

When to use a library: when it is well-maintained, solves a real problem, and you have read enough of the source to trust it. "Not invented here" is a code crime. So is blind dependency on unmaintained packages.

Reversibility by design. Every action in the system must have an equal and opposite action. If a user can create something, they must be able to delete it. If they can rename an entity, they must be able to rename it back. This is not unlimited undo - it is the principle that no action should be a one-way door unless it absolutely must be. When designing an API, a CLI, or a UI: for every verb, ask "what is the inverse?" If there is no inverse, justify why.

## 5. Code Mechanics

### Naming

snake_case for functions and variables. 100% consistent, no exceptions.

Names describe what the thing IS or what the function DOES. No `data`, `result`, `temp`, `val`. A variable holding scan results is `scan_results`. A function that parses vulnerability records is `parse_vulnerability_records`.

`unused_` prefix for tuple elements you do not need:

```python
(port, unused_timestamp, protocol) = parse_entry(raw_line)
```

### Imports

Grouped with section comments. Always in this order:

```python
# Standard Libraries
import os
import sys
from pathlib import Path

# 3rd party
import requests
from lxml import etree

# Local
from localsettings import *
from scan_utils import parse_vulnerability
```

`from X import *` is acceptable for local config modules (`localsettings.py`). Nowhere else.

### Function Structure

Type hints in signatures. Google-style docstrings on public functions. Explicit `return` at end, even for void functions:

```python
def process_scan_file(file_path: Path, output_dir: Path) -> list[dict]:
    """Parse a scan file and return structured vulnerability records.

    Args:
        file_path: Path to the raw scan output file.
        output_dir: Directory for processed results.

    Returns:
        List of vulnerability dictionaries with port, protocol, and severity.
    """
    vulnerabilities = []

    with open(file_path, "r") as scan_file:
        for line in scan_file:
            (port, protocol) = extract_port_info(line)
            vuln_record = build_vulnerability(port, protocol, line)
            vulnerabilities.append(vuln_record)
        #end for
    #end with

    return vulnerabilities
```

### Block-End Comments

C heritage. Mark the end of significant blocks:

```python
if scan_type == "full":
    # ... multiple lines ...
#end if

while remaining_hosts:
    # ... multiple lines ...
#end while

for target in target_list:
    # ... multiple lines ...
#end for
```

### Formatting

4 spaces per indent level. No tabs. PEP 8 standard, enforced by black.

f-strings, not `%` or `.format()`. `pathlib.Path()` over `os.path`. `with` context managers for file I/O. List comprehensions where they read naturally - do not force them.

ASCII separator blocks for major sections:

```python
######################################################################
# Scan Processing
######################################################################
```

### File Structure

Every file:
1. Copyright header (if project uses one)
2. Imports (grouped with section comments)
3. Module-level constants/globals
4. Helper functions (top-down order)
5. Main logic functions
6. `if __name__ == "__main__":` guard

### Control Flow

Maximum 3 levels of indentation inside a function. If you need more, extract a helper or invert the condition with an early return. Deep nesting is a design smell, not a formatting problem.

Minimize return statements. Early returns are acceptable as guard clauses at the top of a function for input validation. After the guards, the function should flow to a single return at the end. No early returns scattered mid-function.

Test empty sequences with truthiness: `if not items:` not `if len(items) == 0:`. Test booleans directly: `if flag:` not `if flag == True:`.

### Configuration

Layered approach:
- Defaults hardcoded in code (always runnable without config)
- Overrides from config files (`localsettings.py` or equivalent)
- Secrets in `.env`, never in code
- Feature toggles and environment checks live in the config layer, not scattered through business logic
- Settings must be easy to find - no hunting through five files

### Tooling (Pre-Commit Enforcement)

A pre-commit hook stack is strongly recommended for enforcing these mechanics automatically. Set up a `.pre-commit-config.yaml` in your repo root with the following tools. Code must pass all hooks before commit:

- **black** - code formatting (line length 88)
- **flake8** - PEP 8 compliance (max-line-length=132 for overflow)
- **isort** - import sorting
- **ruff --fix** - linting with auto-fix
- **mypy** - static type checking with type stubs
- **pydocstyle** - docstring enforcement (aggressive)
- **docformatter** - docstring formatting
- **pyupgrade --py310-plus** - modern Python syntax
- **bandit -ll** - security vulnerability scanning
- **detect-secrets** - credential leak prevention
- **end-of-file-fixer** - all files end with newline

## 6. Testing & Quality

Test-driven development. Write the test first. Watch it fail. Code until it passes.

Unit tests are silver. End-to-end tests are gold. Unit tests prove the parts work. E2E tests prove the system works. Both matter. E2E matters more.

pytest over unittest. Mock external services, never mock the code under test. When mocking, mock at the boundary - the API call, the database query, the file read. Not three layers deep in your own code.

Test everything worth testing. "Worth testing" means: if this breaks, does someone get paged? If yes, test it. Business logic always qualifies. Glue code sometimes qualifies. Formatting rarely qualifies.

### JJ's Rules of QA

**End-to-end testing is what the customer needs. Unit testing helps us nail regressions.** The customer does not care that your unit tests pass. They care that the product works. Unit tests are for developers - they catch regressions early and localize failures. E2E tests are for customers - they prove the system delivers value. Build both, but never confuse one for the other.

**I do not care if it runs in staging. I only care if it runs in production.** Staging increases the probability that production will work, but it is not proof. The ultimate test is: does it run in production? A green staging pipeline is a necessary condition, not a sufficient one. Design your testing strategy with this hierarchy: production truth > staging confidence > local hope.

**Know your tests.** We have many kinds of tests - functionality tests, performance tests, integration tests, smoke tests, chaos tests. Some are good at detecting IF the product works. Others are good at detecting WHERE the product breaks. Know which tool answers which question. A load test will not tell you if the login flow is correct. A unit test will not tell you if the system falls over at 10,000 concurrent users. Use the right test for the right question.

**QA cleans up after itself.** All QA activity must be non-destructive and reversible. Snapshot state before testing. Reverse all changes after. No leftover test data in databases, APIs, or file systems. Log entries are the only acceptable permanent side effect of QA. This applies equally to staging and production.

## 7. Error Handling & Resilience

An exception is a bug that was caught. The code failed to handle an error condition before it became an exception. Code that uses exceptions as flow control is broken code.

The pattern:

```python
def fetch_scan_results(target_host: str) -> list[dict]:
    """Fetch scan results for a target host.

    Args:
        target_host: Hostname or IP to query.

    Returns:
        List of scan result dictionaries.
    """
    if not target_host:
        log.warning("Empty target_host provided, returning empty results")
        return []
    #end if

    try:
        response = scanner_api.get_results(target_host)
    except ConnectionError as conn_err:
        log.error("Scanner API unreachable for %s: %s", target_host, conn_err)
        return []
    except AuthenticationError as auth_err:
        log.error("Scanner API auth failed for %s: %s", target_host, auth_err)
        raise
    except Exception as unknown_err:
        log.error("Unexpected error fetching results for %s: %s", target_host, unknown_err)
        raise
    #end try

    return response.json()
```

Specific exceptions first - ones with known remedies. Then a catch-all for the unknown. There will always be things you do not know that you do not know. Handle the unexpected. Plan for the even-more-unexpected.

Never use bare `except:`. Always catch `Exception` at minimum, so `KeyboardInterrupt` and `SystemExit` pass through.

Validate before you try. Check the condition, do not catch the crash.

Silent errors are a sin. When a function catches an exception and returns a default, the caller must be able to distinguish "no data" from "error occurred." Always return a clear success indicator. Log the error AND make the failure visible to the caller - through a distinct return value, a domain-specific exception, or a success flag. A function that silently returns `{}` on both "empty config" and "corrupt config" is lying to its caller.

Centralize cleanup. Never duplicate cleanup code (closing connections, removing temp files) across multiple return paths. Use `try/finally` or nested context managers so cleanup logic appears once and always runs.

## 8. Security Model

Trust nothing. Validate all inputs. Defense in depth - multiple layers, because any single layer will eventually fail.

Input validation at every boundary. Not just user input - API responses, file contents, database results. Data from outside your control is hostile until proven otherwise.

Third-party libraries are the biggest attack surface. They were the top OWASP issue for decades. Pin versions. Audit dependencies. Assume any open-source library might be broken, have regressions, or contain unknown vulnerabilities.

No hardcoded secrets. No default passwords. No credentials in code, ever. `.env` for secrets, and `.env` in `.gitignore`.

Check for business logic flaws. The security bugs that scanners miss are the ones that matter most. "The user can only access their own records" is a business logic assertion - test it.

Supply chain awareness. Know what you are importing. Typosquatting, dependency confusion, abandoned packages with new maintainers. Verify before you trust.

Permissive licenses only. Third-party dependencies must use permissive licenses - MIT, BSD, Apache 2.0. No copyleft (GPL, AGPL, LGPL) in my code. Check the license before adding any dependency.

## 9. Debugging

**The Two Whys Rule.** Before fixing any bug, ask "why?" at least twice. The first answer is the symptom. The second answer is closer to the root cause. A trivial fix that addresses only the symptom will break again — or mask a deeper design flaw. If the second "why" reveals a structural issue, fix that instead.

Example: "This function returns None" → Why? "The API call fails silently" → Why? "There is no error handling on the HTTP client." Fix the error handling pattern, not just this one call site.

Three steps, in order:

**Step 1: Reproduce.** If you can reproduce it, the fix is usually obvious. Build the minimal reproduction case. Most bugs die here.

**Step 2: Analyze assumptions.** If you cannot reproduce, read the code and find the paths where assumptions break. What did the author assume about the input? About the state? About the order of operations? The bug lives where an assumption is wrong.

**Step 3: Data.** Last resort. Add logging. Print intermediary values. Step through with a debugger. This is expensive - only do it when steps 1 and 2 fail.

Structured logging is the ideal. JSON format, context fields, proper severity levels. Not `print()` scattered through the code. Logging that helps you debug in production without reproducing locally.

## 10. Aesthetic Crimes & Anti-Patterns

**Over-abstraction.** Patterns for patterns' sake. An AbstractFactoryBuilder when a function would do. Every abstraction is a toll booth - the reader pays every time they pass through.

**Cargo cult programming.** Copy-paste without understanding. If you cannot explain why the code works, you do not get to ship it.

**Ignoring the data model.** Building features without understanding the data flow. The code will be wrong in ways that are expensive to fix.

**Show-off code.** Complex regex when three simple string operations would be clearer. One-liners that require a comment to explain. If you need to prove you are clever, you are not writing production code.

**Poor naming.** `data`, `result`, `temp`, `x`, `val`. Generic names are a signal that the author did not think about what the thing actually is.

**Wasteful execution.** Unnecessary API calls. Redundant loops. Loading an entire dataset to use three fields. Every cycle costs money.

**Too many abstractions.** Unnecessary class hierarchies. Inheritance chains four levels deep. If you need a diagram to understand the object model, the object model is wrong.

**Not-invented-here syndrome.** Writing your own HTTP client. Rolling your own auth. If a well-maintained library exists and does the job, use it.

**Hardcoded values.** Magic numbers. Config buried in business logic. Default passwords. Everything configurable goes in config. Everything secret goes in `.env`.

**Putting a whole function on one line.** Comprehensions nested three deep. Lambda chains. The reader's time is more valuable than your character count.

**Blanket suppression of warnings.** `# type: ignore`, `# noqa`, `# nosec`, `# pragma: no cover` applied to entire files or large blocks. If you must suppress a warning, scope it to a single line with a comment explaining why. Broad suppression is admitting the code is broken and you do not want to fix it.

**Spaghetti code.** Control flow that jumps around without clear direction. If you need a diagram to trace execution, the structure is wrong.

**Copy-pasta code.** Duplicated blocks with minor variations. If you copied it, you should have extracted it. Every duplicate is a future bug where one copy gets fixed and the other does not.

## 11. The Rules

### Always

1. Define the data model before writing code.
2. Use snake_case for functions and variables.
3. Group imports with section comments: `# Standard Libraries` / `# 3rd party` / `# Local`.
4. Add `#end if`, `#end for`, `#end while`, `#end try`, `#end with` comments on significant blocks.
5. Put type hints in function signatures.
6. Write Google-style docstrings on public functions.
7. Include explicit `return` at end of functions, even void.
8. Declare functions top-down - defined before called, `main()` last.
9. Use `if __name__ == "__main__":` guard.
10. Use `unused_` prefix for unused tuple elements.
11. Use tuple unpacking for multi-assignment: `(port, protocol) = (vuln["port"], vuln["protocol"])`.
12. Use f-strings for string formatting.
13. Use `pathlib.Path()` for file paths.
14. Use `with` context managers for file I/O.
15. Use `is not None` instead of `!= None`.
16. Catch specific exceptions first, then catch-all `Exception` for the unknown.
17. Validate inputs before processing - check, do not catch.
18. Keep functions to one screen: ~30-50 lines max.
19. Use ASCII separator blocks (`######`) for major code sections.
20. Write tests first. Watch them fail. Then code.
21. Pin third-party dependency versions.
22. Put secrets in `.env`, never in code.
23. Use structured logging with JSON format and context fields.
24. Include copyright headers on every file.
25. Design for lowest cost of execution from line one.
26. Maximum 3 levels of indentation inside a function. Extract or invert if deeper.
27. Test empty sequences with truthiness: `if not items:` not `if len(items) == 0:`.
28. Test booleans directly: `if flag:` not `if flag == True:`.
29. Return a clear success indicator - callers must distinguish success from caught errors.
30. Centralize cleanup in `try/finally` or context managers - never duplicate across return paths.
31. Use stdlib when it fits: `dataclasses`, `collections`, `itertools` over hand-rolled equivalents.
32. Only use third-party libraries with permissive licenses (MIT, BSD, Apache 2.0).
33. For every action in the system, provide the inverse action. Create/delete, rename/rename-back, enable/disable.
34. QA must clean up after itself - snapshot before, reverse all changes after. Log entries are the only acceptable permanent side effect.

### Never

1. Never use exceptions as flow control on the happy path.
2. Never use bare `except:` - always `except Exception` at minimum.
3. Never use `os.path` when `pathlib` will do.
4. Never use `%` formatting or `.format()` - use f-strings.
5. Never name variables `data`, `result`, `temp`, `val`, `x`, or other generics.
6. Never hardcode secrets, passwords, or API keys.
7. Never create a class when functions and a dictionary solve the problem.
8. Never nest comprehensions more than one level deep.
9. Never write a function longer than 50 lines without a very good reason.
10. Never import a library you have not evaluated for maintenance status and security.
11. Never mock your own code three layers deep - mock at the boundary.
12. Never skip input validation because "it is an internal API."
13. Never use `from third_party import *` - only acceptable for local config modules.
14. Never force OOP where procedural is clearer.
15. Never add an abstraction layer without a concrete, current justification.
16. Never use the walrus operator (`:=`). It obscures more than it clarifies.
17. Never swallow errors silently. If you catch it, make the failure visible.
18. Never nest more than 3 levels of indentation inside a function.
19. Never use `if flag == True:` or `if len(items) == 0:` - use truthiness.
20. Never use copyleft-licensed dependencies (GPL, AGPL, LGPL).
21. Never scatter feature toggles or `os.environ` checks through business logic - put them in config.
22. Never apply `# type: ignore`, `# noqa`, `# nosec` to more than a single line. If you must suppress, explain why in a comment.
23. Never duplicate code blocks with minor variations - extract a function.

### Anti-AI Tells (Purge These)

AI-generated code has fingerprints. Strip these before shipping:

1. **Emoji in comments or docstrings.** This codebase has zero emoji. None.
2. **"Let's" or "we" in comments.** Comments describe what IS, not what "we are going to do."
3. **Over-commenting obvious code.** `x = x + 1  # increment x` - the reader is assumed to be keeping up.
4. **Generic variable names.** `data`, `result`, `response`, `output`, `items`. AI defaults to these. Replace with domain-specific names.
5. **Unnecessary docstrings on private helper functions.** Public functions get docstrings. Private helpers are self-documenting through naming.
6. **`Args:` section restating the type hint.** `port (int): The port number` - the type hint already says `int`. The docstring should say what it means, not what type it is.
7. **Defensive `isinstance()` checks everywhere.** Type hints exist. Do not runtime-check what the signature already declares.
8. **Tutorial-style inline comments.** `# Create a list to store results` before `results = []`. If the code needs that comment, the variable name is wrong.
9. **Symmetrical try/except that catches and re-raises without adding value.** Either handle it or let it propagate. Do not catch-log-raise unless the log adds context not available at the caller.
10. **`Optional[X] = None` when `X | None = None` is cleaner.** Use modern union syntax.
11. **Overly polite error messages.** `"Sorry, an error occurred"` - error messages state the fact and the context. No apologies.
12. **Abstract base classes for a single implementation.** YAGNI. Add the ABC when the second implementation arrives.
13. **`self.logger = logging.getLogger(__name__)` in every class.** Module-level `log = logging.getLogger(__name__)` once at the top.
14. **Returning early with bare `return` instead of explicit `return None` on functions that return values elsewhere.** Be explicit about what you are returning.
15. **Missing `#end if` / `#end for` block-end comments.** This is the most visible signature. AI never adds these unprompted.
16. **Walrus operator (`:=`).** AI loves these. This coding style never uses them. Replace with a separate assignment line.
17. **`if flag == True:` or `if len(items) == 0:`.** AI generates these constantly. Use `if flag:` and `if not items:`.
18. **Silent error swallowing.** Returning `{}` or `[]` on error with no way for the caller to know something went wrong. Every error path must be visible.

## 12. Calibration Anchors

These patterns are drawn from real-world production code. This is what "right" looks like.

### Tuple Unpacking - The Signature Move

```python
(port, protocol) = (vuln["port"], vuln["protocol"])
(host, unused_timestamp) = parse_target_line(raw)
```

Parenthesized, explicit, readable. The `unused_` prefix communicates intent.

### Import Blocks

```python
# Standard Libraries
import os
import sys
from pathlib import Path

# 3rd party
import requests
from lxml import etree

# Local
from localsettings import *
from scan_parser import parse_nmap_output
```

Three groups. Section comments. `from X import *` only for local config.

### Block-End Comments

```python
if vulnerability_count > threshold:
    for vuln in critical_vulns:
        report_lines.append(format_vulnerability(vuln))
    #end for
    send_alert(report_lines)
#end if
```

Every significant block gets its closing comment. C heritage carried forward.

### Top-Down Declaration with Section Separators

```python
######################################################################
# File Parsing
######################################################################

def extract_header(raw_content: str) -> dict:
    """Extract scan header fields from raw content."""
    # ...
    return header_fields


def extract_vulnerabilities(raw_content: str, header: dict) -> list[dict]:
    """Extract vulnerability records using header context."""
    # ...
    return vulnerabilities


######################################################################
# Report Generation
######################################################################

def generate_report(vulnerabilities: list[dict], output_path: Path) -> None:
    """Generate formatted report from vulnerability data."""
    # ...
    return


######################################################################
# Main
######################################################################

def main() -> None:
    """Entry point: parse scan files and generate reports."""
    # ...
    return


if __name__ == "__main__":
    main()
#end if
```

Functions defined before called. Sections separated with ASCII blocks. `main()` at the bottom. Guard at the end.

### Error Handling - Validate Before You Try

```python
def load_scan_config(config_path: Path) -> tuple[bool, dict]:
    """Load and validate scan configuration.

    Args:
        config_path: Path to the configuration file.

    Returns:
        Tuple of (success, config_dict). On failure, success is False
        and config_dict is empty.
    """
    if not config_path.exists():
        log.error("Config file not found: %s", config_path)
        return (False, {})
    #end if

    try:
        with open(config_path, "r") as config_file:
            config = json.load(config_file)
        #end with
    except json.JSONDecodeError as json_err:
        log.error("Invalid JSON in config %s: %s", config_path, json_err)
        return (False, {})
    except Exception as unknown_err:
        log.error("Unexpected error reading config %s: %s", config_path, unknown_err)
        raise
    #end try

    return (True, config)
```

Check existence before opening. Specific exception with remedy. Catch-all for the unknown. Success indicator so the caller knows whether `{}` means "empty config" or "broken config." Silent errors are a sin.

### Layered Configuration

```python
# Defaults - always runnable without external config
SCAN_TIMEOUT = 30
MAX_RETRIES = 3
OUTPUT_FORMAT = "json"

# Override from localsettings if available
try:
    from localsettings import *
except ImportError:
    pass
#end try

# Secrets from environment
API_KEY = os.environ.get("SCANNER_API_KEY", "")
```

Defaults in code. Overrides from config. Secrets from environment. Three layers, easy to find.
