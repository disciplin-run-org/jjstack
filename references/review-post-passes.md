# Review post-passes — the five things a finished review still hasn't done

Operating manual for the post-gstack half of the jjstack `/review` wrapper. It is
the base; `skills/review/SKILL.md` cites it and does not restate it.

Phases 2–5 of `/review` produce a verified findings list. That list is the output
of one activity — *reading a diff and judging it* — repeated by many lenses. Five
things stay invisible to every one of those lenses no matter how many you run,
because they are not questions about the diff's contents:

| # | Post-pass | The blind spot it covers |
|---|-----------|--------------------------|
| 1 | Absence | What should have changed and didn't |
| 2 | Auto-fix review | The code the reviewer itself wrote |
| 3 | Prove it | Whether a finding is real, as opposed to argued |
| 4 | Deterministic sweep | Whether the fixes broke the build |
| 5 | Calibration | Whether the reviewer is learning anything |

Every post-pass is **skippable when structurally inapplicable** — no test runner,
no auto-fixes, no prior calibration data. A skipped pass is REPORTED as skipped,
with the reason. Silently omitting a pass and silently passing it look identical
in a report, which is how a dead check survives for months.

---

## Post-pass 1 — The absence pass

**Ask exactly one question: what should have changed and didn't?**

Every reviewer reviews what IS in the diff. Errors of omission never appear in
the text a reviewer is handed, so essentially nothing catches them — which makes
this the highest-value gap in the whole pipeline, not a nice-to-have. The pass is
worth running even when the preceding phases found nothing, because "found
nothing" is exactly what an omission looks like.

Run it as a dedicated pass with a fresh context. For each changed symbol, walk
outward from the change instead of reading the hunk again:

- **Schema / model changed → is there a migration?** And a backfill for existing
  rows, and a rollback path?
- **Enum member, variant, or status added → is every exhaustive consumer
  updated?** Grep the type name and check each `switch` / `match` / `if-elif`
  chain, dispatch table, and serializer mapping. A language without exhaustive
  matching will not tell you.
- **Function/API signature changed → are all callers updated?** Including
  callers in tests, scripts, docs, examples, other repos in the workspace, and
  the public docs that state the old signature.
- **New conditional branch → does a test enter it?** A branch with no test is a
  behavior with no owner.
- **Config key added → is there a default, and does the code path work when the
  key is absent?** Old deployments will not have it.
- **New error case introduced → who handles it?** A raised exception with no
  catch, a returned error code nobody checks, a new failure mode with no log.
- **Behavior removed or renamed → is the caller, the doc, the changelog, the
  feature flag, and the metric name updated too?**
- **New external call → timeout, retry, and failure path?**

Emit absences as ordinary findings, subject to the same Phase 5 verification:
quote the line that creates the obligation (the enum member, the schema column,
the signature) and name the concrete failure — "adding `Status.ARCHIVED` without
touching `render_badge`'s switch means an archived item renders an empty badge
in production", not "the switch may be incomplete".

**Skip only when:** the diff changes no code (docs-only). Say so.

---

## Post-pass 2 — Review the auto-fixes

gstack's review Step 5 is "Fix-First": it classifies findings and auto-applies
the ones it judges safe (Step 5b). **That auto-applied code is an unreviewed
diff.** The reviewer wrote it, so no reviewer reviewed it — it can be wrong,
incomplete, fix the symptom rather than the cause, or introduce a fresh bug in
code that had none. The person who lands the PR usually never sees it as a diff
at all, because it arrives blended into the branch.

This pass has a **prerequisite that runs hours earlier**, and skipping it is what
makes the pass lie. Before anything can auto-apply a fix — i.e. before gstack's
review is delegated to at all — take the baseline marker:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-autofix-diff --mark
```

`--mark` snapshots the dirty tree with `git stash create`, without touching the
working tree or the stash list. It is the only thing that separates *the
reviewer's fixes* from *the user's own uncommitted work*. Without it the baseline
falls back to `HEAD`, and this pass diffs the entire dirty tree — so a user who
had hours of work in progress gets a report full of P1s attributed to an
automaton that wrote none of them. Take the marker; do not rely on the fallback.

Then, after the fixes, get the diff deterministically — do not reconstruct it
from memory of what was fixed:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-autofix-diff --stat
```

Drop `--stat` for the full patch. Baseline resolution is documented in the
script's header; if the output still says it fell back to `HEAD` the marker step
above was missed, and the pass must repeat that caveat in the report rather than
claiming the diff is purely reviewer-authored — and must not report P1s against
work it cannot attribute.

Then review that patch as **a fresh diff from an unknown author**, with the full
Phase 4 lens set. Explicitly re-ask:

- Does the fix actually resolve the finding, or only silence its symptom?
- Is it complete — every occurrence of the pattern, or just the one that was
  quoted?
- Did it change behavior beyond the finding's scope?
- Does it contradict a nearby invariant, comment, or CLAUDE.md rule?
- Is the fixed path tested? An auto-fix is the least-tested code in the branch.

Findings here are **P1 by default**: an unreviewed change written by an automaton
and about to be merged under the banner of a completed review is worse than an
ordinary bug, because its provenance implies it was checked.

**Skip only when:** the script exits 4 (no changes since baseline — no auto-fixes
were applied). Say so.

---

## Post-pass 3 — Prove it with a failing test

For each finding that survived Phase 5 at high confidence, **write the test that
goes red, and run it.**

This is the ultimate false-positive filter. A finding is an assertion; a red test
is evidence. If you cannot make it fail, it is not real — and discovering that
costs one test instead of one round of the user's trust. It also converts the
review's output from a list of claims into a list of regressions someone can
merge.

It is the same rule as the project's RCA method: stop at the **class boundary**,
not at the incident. The test must catch the class of failure, not the single
line that inspired it — if you cannot write a test for the class, you have not
finished understanding the bug.

Procedure, per finding:

1. Write the smallest test that exercises the failure scenario already recorded
   in Phase 5. The scenario IS the test plan; if it is too vague to turn into a
   test, that is a Phase 5 verification defect — report it as one against the
   finding. The finding stays.
2. Run it. Confirm it fails, **and read the failure** — a test that errors on a
   typo or a missing import is not proof of anything.
3. Record the result on the finding as a tag: `PROVEN` (red as predicted, quote
   the assertion output), `DISPROVEN` (the test passed), or `UNPROVABLE`.
4. `UNPROVABLE` is a finding in its own right, never an excuse. Per the project's
   TDD rule, a behavior that cannot currently be tested yields a **failing** test
   — never a hidden, skipped, or deleted one. Report what is missing (harness,
   fixture, seam, injectable clock) as the finding, and keep the red test.

**`DISPROVEN` is an enrichment, not a deletion.** This is the same rule as Phase
5c and it has no exception here: the finding moves into the report's labelled
**Disproven by test** section, carrying the test that failed to go red, and is
never removed. A green test has exactly two explanations and the pass cannot tell
them apart:

- the finding is a false positive, or
- **the test is wrong** — the fixture masks the path, the assertion is weak, the
  wrong seam was exercised.

Deleting on a green test bets everything on the first reading. The failure mode
is precise: a real P0 gets a test that passes for the wrong reason, the finding
vanishes with no baseline entry and no human reason, and post-pass 5 then teaches
the ledger to rank its whole class down forever — through exactly the door the
committed baseline exists to keep shut. Only the baseline, with an explicit human
reason, takes a finding out of the active set.

Then get the proof tests out of the way of post-pass 4: either hand the red test
to the fix in the same pass (preferred — a red test plus its fix is the whole
deliverable), or park it in the report and revert it from the working tree. Never
leave deliberate red tests in the tree while running the sweep; they make a
broken build indistinguishable from a proven finding.

Budget it: prove the P0/P1 findings first, then work down by severity and
confidence. Nothing is filtered out by a threshold — every finding is reported —
so spend the proof budget where a red test most changes what the *reader* does,
which is the top of the report.

**Skip only when:** there are no high-confidence findings to prove, or the
project has no way to execute a test at all (record that as a finding, per
step 4). Say so.

---

## Post-pass 4 — Re-run the deterministic sweep

The typechecker, linter and test suite are the cheapest and most certain
reviewers available, and they cost no tokens. Run them **after** the fixes are
applied — the review has moved the code out from under its own evidence, and a
fix that broke the build or turned a previously-green test red is the most
embarrassing possible way to end a review that reported "all clear".

```bash
~/.claude/skills/jjstack/bin/jjstack-review-sweep
```

The script detects the ecosystem, runs only tools that are actually installed,
prints each check's result, and exits: `0` all green **and a test runner ran**,
`1` at least one check failed, `4` nothing applicable, `5` everything that ran
passed but **no test runner was among the checks**. Override detection with
repeated `--cmd "…"` when the project's real command differs; `--dry-run` prints
the plan (with each check's kind) without running it.

Three outcomes, because "everything I found passed" is a weaker claim than "the
tests still pass". Detection only adds an installed tool, so a Python project
with `ruff` but no `pytest` runs the linter alone — and this pass's whole promise,
catching the fix that quietly turned a passing test red, went untested.

On exit 1: every failed check is a **P0 finding** — the branch does not merge.
Attribute it before reporting: run the same command against the pre-fix baseline
(`git stash` the fixes, or check out the baseline the auto-fix diff used) to tell
"the fixes broke it" apart from "it was already broken". The two are different
bugs with different owners.

On exit 5: report the pass **PARTIAL**, name which check kinds ran and that no
test runner was found, and say the regression question is still open. Never round
a 5 up to a clean sweep — pass `--cmd "<the project's real test command>"` and
re-run instead.

**Skip only when:** the script exits 4. Report SKIPPED with the reason it gives —
never report a skipped sweep as a clean one.

> Note: a companion "before gstack" sweep runs the same checks at review START,
> to establish the pre-existing baseline. When both exist, they share this one
> script; do not add a second implementation.

---

## Post-pass 5 — Calibration persistence

Record which findings the user accepted and which they rejected, so the next
review starts from evidence instead of re-guessing.

Without it the reviewer never learns: the same false positive returns in the same
position forever, and a pattern the user has confirmed three times reads no more
urgently than a first guess. That is how alert fatigue sets in and a report stops
being read. With it, a class the team has repeatedly rejected is **ranked down
the page** under a labelled section that states the prior decision, and a class
they have repeatedly confirmed is **ranked up**. Nothing leaves the report and no
confidence moves — this is ordering, and only ordering.

**Write** one row per triaged finding:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-calibration record \
  --key <pattern-key> --verdict accepted|rejected --lens <pass> --file <path>
```

Choosing the pattern key is the judgment; the arithmetic is not. Key on the
**class** of finding, not the instance — `missing-migration-for-schema-change`,
not `users-table-line-42`. A key that can only ever match once teaches nothing.
Same convention as `pattern_key` in the jjstack memory system.

Record a verdict for every finding whose fate you actually know:
- the user fixed it, or told you it was real → `accepted`
- the user dismissed it → `rejected`
- the user never responded → record nothing. A guess pollutes the ledger.

A post-pass 3 `DISPROVEN` tag is **not** a `rejected` verdict on its own. The
ledger records the team's decisions, and a green test is not a decision — it is
evidence with two readings (see post-pass 3). Show the finding under **Disproven
by test**, let the user rule on it, and record `rejected` only if they do.

**Read** at the start of the next review's verification step:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-calibration report
~/.claude/skills/jjstack/bin/jjstack-review-calibration suggest --key <pattern-key>
```

`suggest` prints a `rank` and a `placement`: `10*accepted - 10*rejected`,
floored at -30 and capped at +20. A negative rank sets `placement=demoted`,
which files the finding under the report's **Demoted (prior decision)** section
— still active, still printed, still carrying its own severity and confidence.

**The rank is placement, never a score.** Phase 5 is enrich-only: verification
may raise a confidence or tag a finding unconfirmed, never lower or delete one.
This pass obeys the same rule, because the confidence score is a claim about the
CODE while a demotion is a claim about the TEAM'S PRIOR DECISION. Conflating
them destroys both — a repeatedly-rejected pattern would come back looking like
weaker evidence rather than like a team that keeps saying no, and a genuine P0
could be arithmetically decayed out of a report by three past dismissals of a
superficially similar finding. Only the committed baseline, which demands an
explicit human reason, removes anything from the active set.

Asymmetric on purpose — under-ranking noise is cheaper to get wrong than
over-ranking it.

The ledger is `{repo}/jjstack/review-calibration.tsv` — version-controlled, so
calibration is a property of the codebase and its reviewers rather than of one
laptop, and so a bad row can be reverted like any other mistake.

**Skip only when:** the script exits 4 (no ledger yet — the first calibrated
review). Say so, apply no adjustment, and still record this review's verdicts so
the next one has data.
