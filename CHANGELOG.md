# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Fixed

- **A mistyped review base is now refused by name instead of quietly reviewing
  nothing.** `/review --base orgin/main` used to sail straight through: the
  blast-radius map printed "Empty diff — nothing to map", the intent pass
  declared your fully committed change "uncommitted", and the evidence pack's
  summary reported both as having run successfully. A base the repo cannot
  resolve now stops the pre-flight before a single pass runs, and says which ref
  it could not find.

- **The evidence pack's summary can no longer say more than the evidence.**
  Every row of the index is now written from what its pass actually found, not
  from whether the pass finished without crashing. A map over an empty diff says
  the diff was empty; an intent pass that recovered no commit message, PR or
  issue says so instead of reporting a claim it never gathered; and the tooling
  row no longer reports "no failures" when nothing ran at all — which used to
  sit one line above the baseline row correctly saying nothing was recorded.

- **The blast-radius map no longer claims your change is self-contained when it
  cannot read its own results.** A repository path containing a character the
  internal text substitution treated as syntax (a `[`, a `|`) silently dropped
  every call site, and the report then affirmatively listed the changed symbols
  as having no callers outside the diff — presenting containment as evidence.
  The same fault affected sibling repositories added with `--also-repo`. Both
  now handle any path.

- **Comments are no longer mined as if they declared code.** A commented-out
  `# class Foo` or `// class Foo` in a Python, JS, Go, Rust, C or SQL change was
  extracted as a real symbol and traced across the repo, burying the genuine
  call sites in noise — despite the documentation already promising comment
  lines were skipped. Whole-line comments are now skipped for real.

- **A project whose linter invokes `/review` can no longer recurse.** The
  re-entrancy guard covered the test command only; `make lint` re-enters just as
  readily. Under re-entry every detected tool is now held back, each recorded as
  skipped with the reason.

- **"Nothing ran" is no longer reported as a clean sweep.** When the only tool a
  repo has times out or is missing, the tooling sweep now exits with a failure
  code instead of zero, so anything reading only the exit status cannot mistake
  it for a pass.

- **Reviewing a tree you do not trust actually works now.** The documented way to
  review without executing anything from the repo —
  `--typecheck none --lint none --test none` — was rejected as an unknown
  argument by the very command the instructions told you to run. The flags now
  pass through.

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
