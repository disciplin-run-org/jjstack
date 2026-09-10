---
id: AR-3
title: /review is bounded by a budget and a convergence rule, not by recall
status: accepted
spec_refs: []
paths: ["skills/review/SKILL.md", "skills/review-lean/SKILL.md", "bin/jjstack-review-preflight", "bin/jjstack-review-tooling-sweep", "bin/jjstack-review-blast-radius", "bin/jjstack-review-intent", "bin/jjstack-pr-comment-lint", "bin/jjstack-review-argcheck.sh", "references/review-preflight.md", "references/pr-comment-voice.md", "test/smoke.sh"]
supersedes: null
superseded_by: null
created: 2026-09-08T17:16:22+00:00
updated: 2026-09-10T21:50:00+00:00
---

# AR-3: /review is bounded by a budget and a convergence rule, not by recall

## Context

jjstack's /review was rebuilt in 2026-09 to maximise recall: force every gstack specialist, disable the small-diff skip, add ten LLM passes, and never delete a finding. Nine stacked PRs implemented it and a second Claude session dogfooded the draft on those same PRs.

The loop did not converge. Measured from git across the stack: main to chain tip was +14,906 insertions against 112 deletions over 33 files; skills/review/SKILL.md went 276 to 1,345 lines, test/smoke.sh 103 to 4,871, and 19 new bin/ tools totalling 6,563 lines appeared. The review-driven fix commits (+12,534) were 2.1x the size of the original feature work they fixed, and exactly one fix in 37 was net-negative. Of ~230 published findings, 75% were P2/P3, and that tier ROSE every round (46, 58, 69) while P0/P1 fell (29, 13, 15). Most of rounds 2 and 3 were the reviewer finding defects in machinery earlier rounds had caused to be written: round 3's P0 was in a linter that did not exist before round 1. Nobody measured whether any of it reviewed better. The reviewer session alone cost $305 and 19.3 hours across 31 subagents.

Three mechanisms drove it, none of them bad taste in any individual finding. First, an inferred mandate ("catch more, take longer, burn more tokens") that the user never issued became the skill's thesis and was pasted into every subagent brief. Second, cost was never a design input: no turn in the build transcripts asks how long a review takes. Third, three governing rules made addition the only legal move - "fix the class, not the fixture", "mutation-prove every new assertion", and "never delete a test" - and the reviewer's own closing recommendation each round ("derive the enumeration from a source of truth") is correct engineering that is strictly more code than the list it replaces.

## Decision

Rebuild /review from main under explicit budgets, and make convergence a property of the process rather than a hope.

Budgets, stated in the skill as rules: 60 minutes wall-clock; Phase 0 under 10 minutes; at most 4 parallel agents in one message; at most 10 findings in the report and 3 in the PR comment. Recall-max (all specialists, no small-diff skip) becomes opt-in behind --deep; without it gstack's own gating applies, because it exists for a reason.

Keep only the passes whose findings had a consequence outside the review tooling: a deterministic pre-flight that runs the repo's real typechecker/linter/tests and treats what they cover as out of scope, maps every changed definition's callers outside the diff from the working tree, and reads the change's stated intent (fenced as untrusted); four judgement passes; per-finding verification with a confidence gate; a three-valued APPROVE/CAUTION/REJECT verdict; and a short PR comment enforced by a linter rather than by asking a model to be brief.

Cut the cross-review memory entirely - the calibration store, the demotion ledger, the suppression baseline, their shared vocabulary and migrator, the per-run triage report, the findings normalizer, the dependency inventory, the post-fix sweep. A re-review reads the previous report and marks each finding new, still open, or fixed.

gstack's auto-fix step is reported, never applied: a reviewer that edits the tree must then review its own edits, and that loop does not terminate.

Convergence rules: a P2-only posture never REJECTs; the author may answer "won't fix" on any P2/P3 and it is not re-argued; a re-review verifies only the prior P0/P1, does not mutation-test the tests a fix added, raises nothing below P1 at all (new or previously listed - barring only re-raised items is what permitted the measured ratchet), opens with the line delta since the last round, and returns STOP when the finding count did not fall.

Every finding carries its simplest fix with deletion considered first, and that fix's size in net lines.

## Consequences

SKILL.md is 293 lines against 1,345; five scripts against nineteen; smoke.sh 200 assertions against 928, running in about 40 seconds. Pre-flight measured at 22 seconds on a 17-file diff.

The rebuild was itself reviewed under the new rules and converged: 23 findings, then 3, then 0, across two fix rounds. 40 mutations were run across the three commits and all were killed; four survived a first pass and were real gaps, each a fix that had been verified by hand and never given an assertion.

Accepted costs. Recall is lower by construction on a small diff unless --deep is passed - a deliberate trade for a review that finishes. Findings dismissed in one review are not remembered by the next beyond what the previous report records and what gstack already tracks. Deleting thirteen tools discards genuine defect fixes that lived only inside them; those are recoverable from origin tags backup/pre-lean-* and backup/pre-lean-wip-pr{17,18,19,24}.

Two limitations stated rather than closed. The independent review round reviewed the replacement using the replacement - the same commit - so a defect in the skill's judgement phases would be invisible to a review run by those phases; three green rounds cannot certify them. And nobody has yet measured whether this reviewer finds more real bugs than main's 276-line version. A seeded-defect baseline (roughly a dozen defects drawn from this repo's own revert and hotfix history, both reviewers run blind, scored on true positives, false positives, misses, wall-clock and tokens) is the only thing that would settle either, and it is deferred by decision rather than forgotten. Until it exists, the 4,423 lines this PR adds are an unmeasured cost.
