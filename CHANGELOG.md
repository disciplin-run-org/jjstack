# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Fixed

- **The permission gate stopped interrupting you every few seconds.** The
  auto-approve hook asked Claude Haiku to rate each command with no context at
  all, so `rm -rf $SP/mut` — a teardown inside a session scratchpad — looked
  identical to `rm -rf` on your home directory and got you a prompt. Any session
  doing heavy scratch work (test harnesses, mutation testing, code review) was
  approving by hand almost continuously. The rater now sees your working
  directory, the tool's own stated purpose, and an explicit statement that
  `/tmp`, `mktemp` directories and throwaway worktrees are ordinary workspace.
  Measured on the real commands that had been prompting: 0 of 6 approved before,
  6 of 6 after, with 11 genuinely destructive commands still refused.
- **The gate got stricter where it matters, not just looser.** A deterministic
  denylist now refuses `rm -rf $HOME`, force-pushes, hard resets, `git clean
  -fdx`, curl-piped-to-a-shell and device writes *before* any model sees them,
  and it overrides a LOW rating. Previously every one of those was a judgment
  call the rater could have gotten wrong.
- **Approvals in a tubemail worker no longer leave a permission stuck pending.**
  The hook had a delegation path keyed on `QM_WORKER_NAME` — a variable nothing
  sets, aimed at a socket that has never existed, so it had been dead code the
  whole time (0 of 638 recorded invocations took it). It now talks to the
  forwarder socket that is actually there, so an approval is paired with the
  request it belongs to. Your local decision stays authoritative: a forwarder
  running the older context-free policy cannot veto it.
- The hook's diagnostic log moved out of the world-readable `/tmp` and is now
  configurable; it records the decision and the reason, not just that it ran.

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
