# The pre-flight evidence pack — what /review knows before it thinks

Operating manual for Phase 0 of the jjstack `/review` wrapper. It is the
companion to `code-review-best-practices.md`: that file says how to judge, this
one says what to gather **before** judging, and why judging without it leaves
whole defect classes structurally invisible.

The pack is built by one deterministic command — no model inference:

```
bin/jjstack-review-preflight --out {OUTPUT_DIR}/preflight
```

which runs four scripts producing six artifacts. This is the
"Algorithm First, Inference Last" rule applied to code review: **never spend a
token on what a compiler, a grep, or a git log already knows.**

## Why a pre-flight at all

Every fast reviewer — Anthropic's `/code-review`, gstack's default — starts by
reading the diff. That makes three assumptions worth naming:

1. that CI already ran the deterministic tools, so the reviewer need not;
2. that the diff contains the evidence needed to judge the diff;
3. that the reviewer has no memory of what it said last time.

All three are false for a **local pre-merge review**. There may be no CI yet.
The evidence for a signature change lives in the file that calls it, which is
not in the diff. And the user's past "no" is on disk, unread. Phase 0 fixes all
three before a single token is spent.

---

## Pre-pass 1 — Deterministic tooling sweep

`jjstack-review-tooling-sweep` → `tooling-results.md` + `exclusions.md`

Anthropic's `/code-review` instructs the reviewer not to report anything "a
linter or typechecker would catch — assume CI runs them." That is correct for a
PR bot, which cannot execute anything. It is wrong for a local review, which
can just **run them**. So we do.

The sweep detects and runs the project's own typechecker, linter and test
suite (best-effort across npm scripts, mypy/ruff/flake8, go, cargo, make
targets, pytest, `test/smoke.sh`, and a `bash -n` parse sweep for shell-first
repos), then produces two things:

- **Real failures** — found deterministically, with zero hallucination risk and
  zero token cost. They go into the report as facts; they need no confidence
  score.
- **An exclusion list** — the explicit "already covered by tooling, do NOT
  report" instruction handed to every AI pass.

**The load-bearing rule of the exclusion list:** a category is marked COVERED
only when the tool covering it actually **ran and passed**. Everything else is
marked IN SCOPE. Excluding type errors because "a typechecker would catch them"
when no typechecker exists is how a review goes silent about exactly the thing
nobody checked. The list never claims coverage it does not have — a `bash -n`
sweep, for instance, is reported as covering parse errors and explicitly *not*
covering style.

Guard: the sweep exports `JJSTACK_REVIEW_PREFLIGHT=1`; if that is already set on
entry it refuses to run the test suite, so a project whose test command invokes
`/review` cannot recurse.

## Pre-pass 2 — Blast-radius map

`jjstack-review-blast-radius` → `blast-radius.md`

gstack's checklist singles out enum completeness as "the one category where
within-diff review is insufficient" — you cannot see a missing switch arm by
reading the enum. That observation generalises. It is equally true of every
renamed function, changed signature, narrowed type and retyped constant: the
defect lives in a file the diff never touches, so a diff-only reviewer is not
*missing* it, it is **blind** to it. The information is simply not in the input.

So the map extracts every public symbol the diff adds, removes or changes
(functions, types, classes, structs, enums, interfaces, exported names,
SCREAMING_CASE constants and enum members, across languages) and uses
`git grep` to find each one's references **outside** the changed files.

Extraction is regex-based and deliberately over-collects: a spurious symbol
costs one empty grep, a missed one costs a bug. Two filters keep that from
tipping into noise — documentation files and comment lines are never mined,
because neither declares anything, and mining them turns ordinary English into
a "symbol" that matches half the repo and buries the real call sites.

Every downstream pass must then ask, per listed call site: does it still hold
against the NEW definition — arity, contract, constant value, exhaustive
handling of every enum member? A call site that no longer holds is a P0 that
appears in no hunk.

Stated limits (say them in the report rather than implying coverage): it sees
tracked files in this repo only — not sibling repos, dynamic dispatch,
reflection, string-keyed lookup, or serialized data.

## Pre-pass 3 — Intent extraction

`jjstack-review-intent` → `intent.md`

"The code does not do what the change claims to do" is undetectable without the
claim. Best practice #6 in `code-review-best-practices.md` is to run an
understanding pass before a judging pass — you cannot run one on evidence you
never collected.

The **gathering** is deterministic (commit messages on the branch, PR title and
body via `gh`, any referenced issue). The **judging** is not, and stays as skill
prose:

1. Restate the claim in one or two sentences before reading the diff critically.
2. Then look for mismatch in both directions — the claim not fully implemented,
   and the diff doing something the claim never mentions (scope creep, or a
   behavior change smuggled in beside the stated one).
3. If no claim was recoverable, say so. Never invent a claim and then grade the
   code against your own invention.

No PR, or no `gh`, is "structurally inapplicable" — recorded as skipped, never
as a failure.

## Pre-pass 4 — Prior-dismissal load

`jjstack-review-prior-dismissals` → `prior-dismissals.md`

Re-reporting a finding the user already looked at and skipped is worse than
missing one: it is pure alert fatigue, and it teaches the author that the
reviewer has no memory. Best practice #10 calls suppressing already-dismissed
findings as important as choosing what to report.

gstack already records a verdict per finding — but applies that memory at its
own suppression step, *after* the passes have burned tokens regenerating them.
Loading the dismissals up front means the passes never produce them.

Source of truth is `gstack-review-read`. **Only the lines before the
`---CONFIG---` marker are JSONL**; past it are the reader's other sections, and
feeding those to a JSON parser is how this quietly turns to garbage. Each
record's `findings[]` carries `{fingerprint, severity, action}`; `action:
"skipped"` is the user's explicit no. The reader keys its history on the current
directory, so it is always run inside the repo under review.

One exception to suppression: re-raise a dismissed finding when the current diff
materially changed the code it points at — the user dismissed it against the
OLD code. Say explicitly that it was dismissed before, and what changed.

## Pre-pass 5 — Test baseline snapshot

`jjstack-review-tooling-sweep` → `test-baseline.md`

Same execution as pre-pass 1, different purpose. It records which tests pass
*right now*, before any review-driven edit, so a later pass can prove the diff —
and any fix gstack auto-applies — broke nothing.

Without a baseline, "tests pass" cannot be distinguished from "tests passed
before too, and still miss this." A **red** baseline is just as useful: failures
present before the review are pre-existing, must not be attributed to the change,
and must not mask a new failure. No runner at all means no baseline, and then no
pass may claim the change broke nothing — that claim is simply unsupported.

---

## How the rest of the review consumes the pack

| artifact | consumed by | as |
|---|---|---|
| `intent.md` | every pass | the claim to compare the code against, read first |
| `exclusions.md` | Phase 2 + Phase 4 | do-not-report list; IN SCOPE categories are still fair game |
| `blast-radius.md` | Phase 2 + Phase 4 | the out-of-diff call sites each pass must check |
| `prior-dismissals.md` | Phase 2 + Phase 4 | fingerprints not to regenerate |
| `tooling-results.md` | Phase 5 / the report | facts, merged in without a confidence score |
| `test-baseline.md` | Phase 5 / the report | the before-state that makes "nothing broke" a comparison |

## Degradation contract

Every pre-pass is skippable when structurally inapplicable — no test runner, no
PR, no review history, no diff — and must **say so** rather than failing the
review or, worse, staying quiet and letting the absence read as a pass. The pack
is written even when every pass had nothing to say, because to a reviewer an
absent artifact and an empty one mean very different things.
