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
  the wrong result), and say what to do about it. Use it before a merge that
  matters; use gstack's `/review` or the code-review plugin when you want fast
  and cheap.
- **`/review` no longer throws findings away.** The verification step used to
  score each finding out of 100 and silently delete anything under 40 — inside
  the one skill built to catch what everything else misses. It now works the
  other way round: verification may add evidence, add a fix, or raise its
  confidence in a finding, and it may mark one *unconfirmed* — but it can never
  remove one. Low-confidence and unconfirmed items move to a clearly labelled
  section further down the report instead of disappearing. If the verification
  step itself fails, every finding passes through untouched and the report says
  so, rather than quietly showing you a shorter list.
- **`/review` now ends in a verdict you can act on.** Reports close with
  `APPROVE`, `CAUTION`, or `REJECT` — `CAUTION` exists so a real concern never
  has to be rounded down to "fine" — plus a per-finding *review judgment* saying
  why each one is acceptable, suspicious, or blocking, and a **Guardrails**
  section listing the conditions under which the verdict holds. If a review pass
  could not run, the report states which one and lowers its own confidence
  instead of presenting a partial review as a complete one.
- **gstack upgraded 1.58.5.0 → 1.81.0.0** for everyone on jjstack. Highlights:
  browsing skills are far more resilient (setup no longer aborts when the
  bundled browser fails to download), gstack no longer clobbers same-named
  skills you own during an upgrade, `/ship` can no longer hang forever on a
  backgrounded subagent, and the upgrade path itself can no longer delete your
  install on a failed swap.

### Added

- **Re-reviews now show you only what is new.** `/review` can keep a small
  baseline file in your repo recording the findings you have already looked at
  and accepted, each with a reason you wrote. Accepted findings stop counting
  and drop out of the active list, but they stay visible in the report marked as
  suppressed, so nothing is ever quietly lost and anyone can see what was waved
  through and why. Two flavours: an exact fingerprint for a single accepted
  finding — edit that code later and the finding comes straight back for a fresh
  look — and a broader pattern rule for a deliberate policy exclusion. A
  suppression without a written reason is rejected outright.
- **Fewer "right bug, wrong line" reports.** `/review` now feeds code to its
  review passes with the line numbers already attached, so a reported location
  is copied rather than counted. It also insists every finding arrive complete —
  including a suggested fix — which quietly removes the findings nobody could
  have acted on anyway.
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
