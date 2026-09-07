# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Changed

- **`/review` is now the deepest review in the stack — on purpose.** It used to
  be a light wrapper over gstack's review. It now deliberately trades time and
  tokens for coverage: it runs *every* specialist (gstack normally skips them on
  diffs under 50 lines and auto-retires ones that have been quiet), and it adds
  eight passes the fast reviewers skip — git history, prior review comments,
  code-comment and CLAUDE.md compliance, plus the security, test-coverage,
  concurrency/resource-leak and error-handling sweeps that Anthropic's
  `/code-review` drops by design. Casting that wide normally means noise, so
  every finding must now survive a verification step: quote the line that
  motivates it, name a concrete failure scenario (the input that triggers it and
  the wrong result), and carry a 0–100 confidence score. Anything under 40 is
  dropped, 40–59 lands in an appendix instead of vanishing silently, and the
  main report is ranked by severity. Use it before a merge that matters; use
  gstack's `/review` or the code-review plugin when you want fast and cheap.
- **gstack upgraded 1.58.5.0 → 1.81.0.0** for everyone on jjstack. Highlights:
  browsing skills are far more resilient (setup no longer aborts when the
  bundled browser fails to download), gstack no longer clobbers same-named
  skills you own during an upgrade, `/ship` can no longer hang forever on a
  backgrounded subagent, and the upgrade path itself can no longer delete your
  install on a failed swap.

### Added

- **`/review` now looks outside the diff — at the rest of your repo, and at your
  repo's past.** Two things a diff-only reviewer structurally cannot catch, now
  computed before the review starts. First, the **blast radius**: for every
  function, class or constant whose definition your change touches, `/review`
  lists every place in the repo that still calls it and that your diff did *not*
  update — the "you changed the signature, three callers elsewhere are now
  broken" class of bug. Point it at sibling repos too when a shared module's
  consumers live in another checkout. Second, the **revert history**: which of
  the files you are touching have been reverted, rolled back or hotfixed before,
  with the commits named, so a change that quietly reintroduces an old incident
  gets flagged as a P0 instead of sailing through.
- **`/review` remembers what you already decided — without ever going quiet on
  you.** Findings you adjudicate can be recorded in a ledger at
  `jjstack/review-ledger.md` in your repo, and future reviews check against it.
  A finding you previously dismissed moves to the report's appendix with your own
  note quoted as the reason — it is **demoted, never dropped**, so you can always
  see what was set aside and why. Security, correctness, concurrency,
  error-handling, resource-leak and test-coverage findings never demote at all,
  however many times they were waved off; those are the classes where a wrong
  suppression ships an incident. And unlike the hosted tools this idea came from,
  the memory is a plain file in git: a suppression is reviewable in a PR, and
  retiring one is a visible diff instead of a setting nobody can audit.
- **`references/vendor-lessons-greptile.md`** — the homework behind the above.
  What Greptile's reviewer verifiably does, which of its claims are real
  mechanics and which are unfalsifiable marketing (their headline benchmark
  scores bugs caught while *excluding false positives from scoring*, so it
  measures recall only), and an explicit list of what jjstack adopted, what it
  rejected, and why. Useful on its own if you are evaluating AI review tools.
- **Reviews now keep the rubric that produced them.** `/review` snapshots
  gstack's durable review docs (the checklist, every specialist definition, the
  Review Army and adversarial procedures) into your repo next to the findings,
  stamped with the gstack version and commit they came from. Previously that
  rubric lived only in the global gstack clone, which upgrades rebuild from
  scratch — so a six-month-old review was uninterpretable, and nothing recorded
  that the standard had shifted underneath it. Now the git diff on those files
  is a visible record of when the review bar changed.
- **`references/code-review-best-practices.md`** — the sourced manual behind
  `/review`: how Anthropic's and gstack's reviewers are actually tuned, twelve
  ranked practices for high-recall/low-noise AI review, the dimension checklist,
  and the anti-patterns that make a reviewer untrustworthy.

- **A real cross-session memory that recalls, captures, and consolidates
  lessons.** jjstack now remembers what you've taught it and surfaces it when
  it matters. Every prompt quietly recalls the relevant notes — this project's
  own lessons, your pan-project preferences ("how you like things done
  regardless of repo"), and lessons from your other projects — matched by
  meaning, not just keywords. When a session ends, durable lessons are captured
  automatically (no more remembering to run a save command). And `/groom cross`
  finds things you've told several projects and promotes them to one shared
  place, so the same lesson stops living in five copies. Sensitive projects opt
  out and keep their memories local-only. Turn auto-capture off any time with
  `JJSTACK_NO_CAPTURE=1`.
- **The Definition of Done is now a version-controlled reference.** The
  "done-done" checklist that decides when work may be called *done* now
  lives in the repo at `references/definition-of-done.md` as the single
  canonical source, instead of only in a machine-local config file. The
  skills that gate on completion cite it directly, so the rules travel with
  jjstack and stay in sync.
- **Two new done-done rungs.** Calling something "done" now also requires
  updating the change log with an end-user summary (this file) and keeping
  the README reflecting the product's current state — extending the
  checklist from 8 rungs to 10.
