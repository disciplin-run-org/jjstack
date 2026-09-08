# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Fixed

- **A `/review` run can no longer lose every finding it made.** One field the
  model got wrong — a `confidence` of `null` instead of a number — used to crash
  the step that checks findings before they reach the report. The crash happened
  before anything was written out, so the run ended with an empty report, no
  record of the bad finding, and an exit code indistinguishable from "a couple
  of findings were malformed". Real blocking issues disappeared and nothing said
  so. Findings are now written out as they are checked, a bad field is recorded
  and skipped rather than fatal, and a genuine internal failure has its own exit
  code so a crash can never be read as partial success. This now holds for
  *any* failure, not just the one that was reported: whatever goes wrong while
  checking a single finding, that finding is written to the malformed file with
  the reason and the line number, and the rest of the run continues. The
  malformed file is also rewritten on every run, so it always describes the run
  that just finished instead of leaving yesterday's records lying around.
- **A single baseline entry can no longer mute your whole repo.** A suppression
  rule of `{"path": "*"}` matched every finding, so the review reported nothing
  active and approved the change. Rules must now name something real; a rule
  made only of wildcards is rejected with an explanation. Rules may spell the
  same thing two ways (`id`/`rule_id`, `path`/`file`); the check now reads
  whichever spelling actually applies, so a wildcard can no longer hide behind a
  narrow-looking twin.
- **Extending a review baseline no longer erases the one you had.** Running the
  documented "extend the baseline" command on a repo that already had one
  rebuilt the file from scratch, throwing away every previously accepted finding
  and the reasons a human wrote next to them. It now merges; `--replace` is the
  explicit way to start over, and a corrupt existing baseline stops the run
  instead of being overwritten.
- **Feeding a file to a review pass now fails loudly instead of silently
  passing it nothing.** If the file could not be read, the line-numbering step
  reported success on empty output — and a pass handed an empty file reports
  zero problems, which looks exactly like clean code.
- **Capturing a lesson no longer has to reach the network to tell you what it
  would do.** `jjstack-capture-write --dry-run` was querying the live gbrain
  index before printing its plan — so a preview that changes nothing still
  waited on a remote lookup, and its answer drifted as the index grew. Set
  `JJSTACK_CAPTURE_NO_GBRAIN=1` to pin the semantic dedup layer off for a fast,
  repeatable answer (useful offline or air-gapped); duplicate detection by
  pattern key still runs, so dedup is reduced rather than silently skipped. The
  dry-run output now states which dedup layers ran instead of leaving you to
  guess. The test suite uses this, and went from intermittently failing to
  stable — and from seconds of waiting to under three.
### Added

- **`/review` now gathers evidence before it starts thinking.** A new pre-flight
  step runs before any AI pass and costs no judgement at all, because none of it
  is guesswork:
  - **It runs your actual tooling.** Your typechecker, linter and test suite are
    executed for real, and whatever they find goes into the report as fact.
    Reviewers normally skip this whole category on the assumption that CI covers
    it — which is fine for a bot commenting on a PR and wrong for a review you
    run locally before merging, where the compiler is right there.
  - **It tells the review what NOT to look at — but only what was really
    checked.** A category is marked "already covered" only when the tool
    covering it actually ran and passed. If you have no typechecker, type
    problems stay firmly in scope instead of being waved through.
  - **It maps what your change reaches outside itself.** Every public thing the
    diff touches — function, type, constant, enum member, exported name — is
    traced to the places that use it in files the diff never opens. That is the
    bug a diff-only review cannot see by construction: you rename a function,
    the caller two directories away still uses the old name, and nothing in the
    diff shows it. Those call sites are now handed to every pass.
  - **It reads what the change claims to do** — your commit messages, the PR
    body, any linked issue — before judging it, so "this doesn't actually do
    what it says" becomes a finding instead of an invisible gap.
  - **It remembers what you already said no to.** Findings you dismissed in a
    past review are loaded up front so the passes never regenerate them. Being
    told the same thing you rejected last week is how a reviewer loses your
    trust.
  - **It records which tests pass right now**, so anything the review changes —
    including fixes applied automatically — can be shown not to have broken
    something that worked.

  Anything genuinely not applicable (no test runner, no PR, no review history)
  is reported as a known gap rather than quietly reading as a pass.

- **A gbrain lookup that failed no longer claims it ran clean.** The dry-run's
  dedup report used to say `ran-clean` — "semantic dedup ran and found no
  duplicate" — whenever the lookup did anything other than time out. A corrupt
  or unreadable index, a gbrain binary that had been moved, or a bad deadline
  value all produce the same empty result as a genuine no-match, so the run
  reported success while doing nothing. Those cases now report
  `ran-error:<code>` and their empty answer is discarded rather than believed.
  `ran-clean` again means only what it says.

- **The gbrain lookup deadline is documented and adjustable.**
  `JJSTACK_CAPTURE_GBRAIN_TIMEOUT=<seconds>` (default 8) sets how long capture
  waits for the semantic dedup query. On a slow link or a large index, raise it
  instead of turning dedup off entirely — previously the only documented remedy
  was `JJSTACK_CAPTURE_NO_GBRAIN=1`, which removes the layer altogether.

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
