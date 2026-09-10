# Definition of Done — "done-done"

The single canonical, version-controlled definition of what "done" means
across every jjstack session, worker, and work order. Skills and the
machine-local global `~/.claude/CLAUDE.md` cite THIS file as the source of
truth — when the definition changes, change it here first.

When someone asks "is it done-done?" — or when an agent claims anything is
done — this is the one checklist. ALL rungs, no exceptions.

## The 11 rungs

1. **Code complete** — implemented, no TODOs in the delivered path.
2. **Unit tests green** — written/updated and passing.
3. **Committed** (conventional message) **and pushed** to origin.
4. **Independently reviewed** — a session that did NOT author the commits
   ran `/review` on the PR under the reviewer GitHub identity, and its
   newest round is a GitHub review in state APPROVED. The state is the
   condition, not any particular wording: `/review` approves with
   non-blocking findings listed, so requiring a literal `lgtm` line would
   refuse a verdict the skill legitimately returns. Every blocking finding
   it raised is fixed or answered on the
   thread, and **every push that answers findings is followed by a
   re-request**: the merge waits for an APPROVED review newer than the last commit,
   never for the round that raised the findings. A round the author runs on
   their own PR does not satisfy this rung, whatever it concludes: the same
   context that wrote the code cannot audit it. It is not forbidden and
   `/review` does not refuse it - the reviewer's previous-round detector
   filters on the posting account, so a self-check costs the real reviewer
   nothing. It is simply not the review the merge waits on. Who must approve depends on the
   repo's class — the table and the protocol are in
   `references/independent-review.md`:
   - **InboundSavvy repos** (`codebase`, `web-checks`,
     `workflow-automation`, `-cms`, `webmaster`, `brand-system`,
     `inboundsavvy.com`, `site-templates`; not `e2e`): the AI
     review first, then at least one human reviewer — Andre or Santiago,
     never Jesper — requested only after the AI round is clean.
   - **disciplin.run org repos and Jesper's other repos**: one AI review is
     enough.
5. **Merged to main** — PR merged, dangling branch deleted.
6. **Deployed** — container/service rebuilt and restarted; the change is
   running live, not just sitting in git.
7. **QA green** — iris-qa BDD tests pass against the LIVE surface (where
   iris-qa covers the repo; otherwise the project's e2e equivalent).
8. **Documented** — specs updated (UX decisions), ADR filed via Architrix
   (architecture decisions), docstrings current.
9. **Released to consumers** — ready for the end-user acceptance test:
   loaded, integrated, observable in the real product.
10. **Change-log updated** — a high-level, end-user-facing summary of what
    changed this cycle appended to the project's change log (`CHANGELOG.md`
    or equivalent). Written for the person who USES the product, not the
    person who reads git history: what's new or different and why it
    matters, NOT the commit-level detail. If no change log exists yet,
    create one.
11. **README reflects current state** — the README describes the product
    AS IT NOW IS after this change (features, usage, setup, status). The
    README is a living description of the present product, NOT a change
    log — do not accrete a running history of edits into it; update the
    affected sections in place so a first-time reader sees today's truth.

## Reporting rule

The unqualified word "done" MAY ONLY be used when all 11 rungs hold.
Anything less is reported as **"done N/11"** naming the missing rungs
(e.g. "done 3/11 — committed+pushed; not reviewed, not merged, not
deployed, no QA run, changelog/README not updated"). Never make the human
ask "did you push it?", "who reviewed it?", or "did you update the
changelog?".

When a rung genuinely does not apply to a change (e.g. a docs-only change
has no deploy step, a rule-definition change has no unit-test surface),
say so explicitly in the report rather than silently dropping it — an
inapplicable rung is named, not omitted.

## What "independent" means

A different Claude Code session from the one that authored the commits:
its own working directory (a worktree or clone), launched fresh — not a
`--continue` of the author's session, and not a subagent of it. The
reviewer session holds the reviewer identity's token, so the review lands
as a GitHub review that branch protection can require. The identity is a
prerequisite, not a nicety: a PR whose author holds the only token on the
machine cannot pass this rung at all: GitHub refuses an approving review on
your own PR (HTTP 422), so the round can only ever post as a comment and
`reviewDecision` never moves. `/review` still runs and still says so in its
close-out. Until the identity exists, such a PR is "done 3/11 — blocked on
rung 4".

## Scope

This applies to every session and every worker (orchestrators, coders, UI
sessions) and to every work order written: put
"DONE = done-done (all 11 rungs) or report done N/11" in the order's Done
section.

## Where this lives

- **Canonical source:** this file — `references/definition-of-done.md` in
  the jjstack repo (`github.com/disciplin-run-org/jjstack`). Reachable at
  runtime through the `~/.claude/skills/jjstack` symlink.
- **Machine-local mirror:** the "Definition of Done" section of
  `~/.claude/CLAUDE.md` carries the full text so it is auto-loaded into
  every session. That mirror is hand-maintained and cites this file;
  update this file first, then reconcile the mirror. The one-line
  `done-means-done-done` row in `~/.claude/memory/always-rules.md` is a
  second mirror, surfaced by the shared-memory hook on every prompt.
- **Skills that cite it:** `verify-before-done`, `work-order`,
  `qa-build-loop`, `review`, `receiving-code-review`, and any skill whose
  completion gate references "done-done". Skills point here instead of
  re-inlining the full rung list, so a rung change touches this file (+ the
  two mirrors), not every skill.

## History

- Originated as an 8-rung checklist in the machine-local global
  `~/.claude/CLAUDE.md`.
- Extended to 10 rungs (added rung 9 change-log and rung 10 README) and
  captured here as the version-controlled canonical source.
- Extended to 11 rungs (2026-09-10, PR #39): rung 4 "Independently
  reviewed" inserted before "Merged to main". Eight merged PRs in a row had
  carried zero reviews; `main` had no protection; and the author's session
  was the only one that ever looked. See AR-6. The rung caught a defect in
  its own PR on the first independent round: the branch had been cut before
  PR #30 merged, no longer merged cleanly, and would have reverted five
  landed items - which is exactly what a session reviewing its own branch
  cannot see.
