---
id: AR-6
title: A PR is merged only after a session that did not write it approves it, and after every push that answers findings
status: accepted
spec_refs: []
paths: ["references/definition-of-done.md", "references/independent-review.md", "skills/review/SKILL.md", "skills/review-lean/SKILL.md", "skills/work-order/SKILL.md", "skills/verify-before-done/SKILL.md", "skills/qa-build-loop/SKILL.md", "skills/receiving-code-review/SKILL.md", "test/smoke.sh", "test/fixtures/pr-stale-approval.json", "README.md", "CHANGELOG.md"]
supersedes: null
superseded_by: null
created: 2026-09-10T02:51:43+00:00
updated: 2026-09-10T21:50:00+00:00
---

# AR-6: A PR is merged only after a session that did not write it approves it, and after every push that answers findings

## Context

The Definition of Done said "merged to main" and never said who had to look at it first. Measured on this repository on 2026-09-09: the last eight merged pull requests carried zero GitHub reviews and an empty `reviewDecision`; `main` had no branch protection; every review that ran was run by the session that wrote the code. AR-3 had already named the limit of that: "the independent review round reviewed the replacement using the replacement, so a defect in the skill's judgement phases would be invisible; three green rounds cannot certify them."

Two facts about GitHub shape the answer. A user cannot approve their own pull request - `--approve` returns HTTP 422, `Can not approve your own pull request` - so under one account the verdict can only ever be a comment, `reviewDecision` never moves, and no branch rule can require anything. And branch protection with a required approval is free on a public repository in a free organisation, which this is.

AR-6 was first written against a branch cut from `370abc3` that also rebuilt the posting mechanics: a `SELF_REVIEW` refusal, a `bin/jjstack-review-previous-round` tool, and a `gh pr review` post chain. PR #30 merged as `672f5da` while that branch was open and delivered all of it, with three differences that are each strictly better - `PR_ME` guarded against jq's literal `null` on a failed `gh` call, a previous-round detector that filters on the posting account rather than on the body prefix alone, and a review event bound to the verdict through a substituted `<EVENT>` rather than a hardcoded `--approve`. The first independent review of the branch found the collision, verified that the merge conflicted, and rejected it: resolving toward the branch would have deleted the authenticity filter that #30's own review round had raised as a P0. The branch was rebased onto `main` and only the policy delta re-applied. That episode is the first evidence for the decision recorded here, and it is why the mechanics below are cited rather than restated: they belong to #30.

## Decision

Independent review becomes rung 4 of the Definition of Done. The definition goes from 10 rungs to 11 and the reporting form becomes "done N/11". `references/independent-review.md` carries the protocol both sides follow, the repo-class table, and the GitHub settings; the definition, the `~/.claude/CLAUDE.md` mirror and the one-line `always-rules.md` mirror cite it.

**The rung keys on the review state, not on any wording.** An earlier draft required the literal `lgtm - approved` line. `/review` approves with non-blocking findings listed, which is a verdict it legitimately returns, so that draft was unsatisfiable on any pull request that had ever carried a finding. The condition is a GitHub review in state APPROVED.

**The rung is a loop, not a gate crossed once.** Every push that answers findings is followed by a re-request, and the merge waits for an APPROVED review newer than the last commit. The round that raised the findings never counts as the approval for the commits that answered them. Branch protection expresses this as `dismiss_stale_reviews`; where it is not enabled the author checks the two timestamps with the command the protocol reference carries, and `test/smoke.sh` recovers that command from the document with `sed` and executes it against a fixture whose commit is deliberately newer than its approval.

"Independent" means a different Claude Code session from the one that authored the commits: its own working directory, launched fresh, never a `--continue` of the author's session and never a subagent of it. It is a different context window of usually the same model family, not a different reviewer in the human sense.

Who must approve depends on the repository's owner. On InboundSavvy repositories - `codebase`, `web-checks`, `workflow-automation`, `-cms`, `webmaster`, `brand-system`, `inboundsavvy.com`, `site-templates`; `e2e` excluded - the AI review runs first and then at least one human, Andre or Santiago and never Jesper, so the human reviews a converged pull request rather than a draft. On disciplin.run repositories and Jesper's other repositories one AI review is enough.

The reviewer has its own GitHub identity: the machine user `ai-assistant-2026`, created 2026-09-10, an outside collaborator with write access on 55 repositories, holding a **classic** token with the `repo` and `read:org` scopes, issued 2026-09-10 and expiring 2027-09-10. Classic rather than fine-grained because a fine-grained token cannot reach repositories its user only collaborates on. The token lives in a second `gh` config directory, `~/.config/gh-ai-assistant-2026/hosts.yml`, and the reviewer directory's `.env` points `GH_CONFIG_DIR` at it; it is never exported as `GH_TOKEN`, which every Bash call in a session would inherit and `env` would print. The worker keeps its directory-derived tubemail name - identity and worker name are independent axes. A GitHub App was considered and rejected: correct for a product, more machinery than one reviewer needs, and `gh` does not speak App installation tokens without a helper.

`/review` is not changed mechanically by this decision. Its self-authored branch, from #30, already posts `--comment` and says the state could not be set; the rung adds one sentence naming what else that costs - the round does not satisfy rung 4 - so the author reads it in the close-out rather than inferring it from a missing green check. It is explicitly not a refusal to run: #30's author filter keeps a self-check out of the real reviewer's previous-round detector, so the round costs the reviewer nothing.

`main` gets branch protection once the identity has approved a pull request on it: one required approving review, `dismiss_stale_reviews`, the `verify` check required, `enforce_admins` false so an admin keeps an escape hatch, no push restrictions. Using the escape hatch is reported as "merged without review", never silently. On an InboundSavvy repository the count is 2 and the block also sets `require_code_owner_reviews`, without which a `CODEOWNERS` file is inert - GitHub requests the owners and requires nothing, so two AI approvals would satisfy a count of two.

## Consequences

Accepted. Every pull request now waits on a second session, and on an InboundSavvy repository also on a person's calendar. The wait is the point.

Accepted. One more identity to hold and one token to rotate, on a date this record carries.

Accepted. GitHub cannot express "one of the two approvals must be a human". `require_code_owner_reviews` plus a `CODEOWNERS` naming only Andre and Santiago is the closest available, and the rest stays prose. Enabling protection on the InboundSavvy repositories is owned by their maintainers.

Gained. A review is a GitHub review, so `reviewDecision` moves, review requests work, and `dismiss_stale_reviews` voids an approval mechanically when a commit lands after it.

Gained, and this is the strongest evidence the decision has. The rule caught a defect in its own pull request on the first round: an author-run review would have been run by the session holding the branch, against the branch, and would not have looked at what merged to `main` while the branch was open. The independent reviewer's first finding was that the branch no longer merged and would revert five landed items. That is precisely the class AR-3 said a self-review cannot see.

Learned. Rung counts are cited in more places than anyone remembers - the canonical file, two machine-local mirrors, four skills, the README, a memory file - and the 8-to-10 bump left stale references behind. This one was swept by grep across all of them.

Learned. Before opening a pull request, read the OPEN ones. The collision above was avoidable: the branch was cut after checking merged pull requests only, and #30 was open at that moment, touching the same two files.
