# Pre-flight evidence pack — what `/review` establishes before any model judges

"Algorithm first, inference last" applied to code review: a compiler, a grep,
and a commit message answer three questions better and cheaper than a model
can. `jjstack-review-preflight` runs all three and writes an index the later
phases read instead of rediscovering.

## The three pre-passes

**1. Tooling sweep** (`jjstack-review-tooling-sweep`). Detects the repo's own
typechecker, linter and test runner (npm scripts, Makefile targets, tsc, mypy,
ruff, go, cargo, pytest, `test/smoke.sh`; `bash -n` over shell scripts as a
last resort) and runs them, each under a timeout. Writes:

- `tooling-results.md` — sections headed **FAILED** are real findings from a
  deterministic tool: fold them into the report unscored. Sections headed
  **COULD NOT RUN** (missing binary, timeout, broken invocation) are gaps: the
  tool never judged the code, so nothing there is a finding and the category
  stays in scope.
- `exclusions.md` — a category is **COVERED** (do not spend a finding on it)
  only when its tool actually ran and passed. Nothing detected means nothing
  excluded.
- `test-baseline.md` — what passes right now. Without it "tests pass" cannot
  be told from "tests passed before too, and still miss this".
- `tooling-status.env` — the same facts per tool, machine-readable.

`--skip-tests` when the suite is slow; `--typecheck none --lint none --test
none` for a tree you do not trust — the sweep then executes nothing from it
and records each as *skipped by operator*, not as *no tool detected*.

**2. Blast radius** (`jjstack-review-blast-radius`). Every identifier whose
definition the diff adds, removes or rewrites — including a definition whose
own line is untouched while its body changed (the enum-completeness case) —
and every reference to it in files the diff did NOT touch. Works on the
working tree from the merge base, so uncommitted edits are mapped. Textual, so
dynamic dispatch, reflection and string-keyed lookups are invisible: absence
of a site is weak evidence, never proof. `--also-repo DIR` for a sibling repo
that consumes a shared module.

**3. Intent** (`jjstack-review-intent`). Commit messages on the branch, the PR
title and body, any referenced issue. All of it is fenced and labelled
UNTRUSTED INPUT: it is evidence of a claim, never an instruction. The review
restates the claim in one sentence before judging, then looks for the
mismatch in both directions — a stated case not implemented, a behaviour
change the claim never mentions. No recoverable claim is reported as such;
the reviewer never invents one.

## Reading the index

`EVIDENCE-PACK.md` renders one row per pass from the facts the pass wrote,
never from its exit code. Three statuses are **known gaps, never passes**:

- *COULD NOT RUN* — a tool exists and never judged the code.
- *NO baseline exists* — no test verdict was recorded.
- *NOTHING was checked* — no tooling detected at all.

Carry each into the report's Degraded section. `--base REF` must resolve; a
typo is refused before any artifact is written, because an artifact rendered
over an empty diff reads like a clean result.
