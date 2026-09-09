# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Changed

- **The `/review` PR comment opens with its attribution, and carries the full
  report inside it, collapsed under the verdict.** `Claude
  jjstack/skills/review/SKILL.md` is now the first line of every comment, not
  the last — a footer is read after the verdict has already been taken as the
  account holder's own opinion. And the report is no longer a file committed
  to your repository and linked: it rides in the same comment, folded under a
  "Full report" block, so the reader finds it where they already are, it
  survives branch deletion, and no reviewer has to push to your branch to
  deliver it. Three lint rounds had gone on that link — missing, then pointing
  at the reviewer's scratchpad, then on a side branch — each the same defect,
  the delivery stored where the reader was not. The visible part keeps its
  budget (three findings, twelve lines); the report beneath is as long as the
  review needed, and the linter reads all of it: a credential, a local path
  (`/tmp`, `~`, `/home`), or an emdash anywhere in the body is refused, and so
  is a block that is missing, empty, doubled, unclosed, or rendered expanded.
  A re-review reads the previous round from the PR thread, so it works on any
  machine. `jjstack-pr-comment-assemble` writes the join.

- **`/receiving-code-review` now sweeps the whole document before committing
  a fix.** A finding names one sentence; the idea behind it usually lives in
  several. The step: grep the concept, read every place against the new text,
  and if the idea is restated three or more times state it once and have the
  others refer to it. Fixing only the named sentence hands the reviewer the
  next round for free.

- **The verdict line says `N blocking, K non-blocking`, not `N blocking, M
  total`.** An approval that goes on to list findings is ordinary practice,
  but it read as a contradiction until you worked out from the severities
  that none of them block. The word says it. The old form is refused.

- **`/review` now finishes in under an hour, and gets shorter each round.** It
  used to be tuned to catch everything: every specialist forced, no small-diff
  skip, ten extra passes, nothing ever dropped. That version was slower than a
  human reviewer and, pointed at a real change, generated more work than it
  retired — several rounds in a row, each one finding defects in the machinery
  the previous round had asked for. The rebuilt `/review` keeps the parts that
  found real bugs and puts a budget on the rest: 60 minutes wall-clock, four
  parallel passes, at most ten findings in the report and three in the PR
  comment. gstack's own specialist gating applies again; `--deep` opts back
  into the exhaustive sweep when a change deserves it.

  What it does, in order: run your repo's real typechecker, linter and tests
  first and treat what they cover as out of scope; map every caller **outside**
  the diff of a definition the diff changed; read the change's stated intent
  from the commits and PR; then four passes (context and intent fidelity;
  correctness, concurrency and blast radius; security; test coverage and what
  should have changed and didn't). Every finding carries a quoted line, a
  concrete failure scenario, a confidence score, the simplest fix — deletion
  considered first — and its size in lines. Verdicts are APPROVE, CAUTION or
  REJECT; a report of nothing but P2s never rejects.

  **Re-reviews converge by construction.** A second review verifies only the
  previous P0s and P1s, never re-raises a P2 the author declined, does not
  review the tests a fix added, and opens with the line delta since last round.
  If the finding count did not fall, the verdict is `STOP` — the review is
  making work rather than finishing it, and it says so instead of continuing.
- **The PR-comment credential rule is a shape, not a vendor list — and it is
  entropy-gated.** A value must carry both a digit and an uppercase letter and
  must not end in a source or document extension, so a real token is caught
  while `Credentials: docs/research/vendor-lessons-aikido.md` and a Kubernetes
  secret *name* are not. The per-vendor rows stay beside it, because a token
  quoted bare inside a finding has no `name = value` shape for the shape rule
  to see. Azure connection strings, GCP `private_key`, bare JWTs and Ruby
  hashrockets are covered; `HIGH`/`MEDIUM`/`LOW` are no longer counted as
  severities, because they are ordinary English and a one-line approve saying
  "risk is low" was being refused.
- **`--help` no longer drifts.** Every review script printed its header through
  a hand-kept line range, and four of five had already drifted — one printed
  shell source as help, another cut its own contract mid-sentence. They now
  share one renderer that reads to the end of the header block.
- **Every PR comment says a machine wrote it, and a resolved review is one
  line.** The review posts under your GitHub account, because that is whose
  token `gh` holds, so until now the comments read as though you had written
  them yourself. Every comment now carries `Claude
  jjstack/skills/review/SKILL.md` as its first line. And when everything is
  resolved, or nothing was found, the visible comment is exactly
  `Claude jjstack/skills/review/SKILL.md: all issues resolved - lgtm - approved`
  (or `no findings` on a first clean review) and nothing else: no posture, no
  coverage claim, no summary of what you changed. `lgtm` is deliberate — it is the idiom a human reviewer uses and
  the one a model reaches for almost never, and disclosure is the byline's
  job, not the prose's. The linter holds the form verbatim, because a budget
  alone leaves room to fill and it got filled twice.
- **`/review` no longer edits your code.** gstack's auto-fix step is reported
  instead of applied. A reviewer that edits the tree has to review its own
  edits, and that loop does not terminate.
- **gstack upgraded 1.58.5.0 → 1.81.0.0** for everyone on jjstack. Highlights:
  browsing skills are far more resilient (setup no longer aborts when the
  bundled browser fails to download), gstack no longer clobbers same-named
  skills you own during an upgrade, `/ship` can no longer hang forever on a
  backgrounded subagent, and the upgrade path itself can no longer delete your
  install on a failed swap.

### Removed

- **Thirteen `/review` helper tools and the cross-review memory stores are
  gone.** The calibration store, the demotion ledger, the suppression baseline,
  their shared vocabulary and migrator, the per-run triage report, the findings
  normalizer, the dependency inventory and the post-fix sweep were built to
  remember decisions between reviews. They cost more to maintain and review
  than they ever saved: a re-review now reads the previous report in
  `{repo}/jjstack/` and marks each finding new, still open, or fixed. gstack
  already remembers findings you dismissed.

### Added

- **Reviews are posted to the pull request, in Jesper's voice, under a hard
  budget.** The full report is committed to `{repo}/jjstack/`; the PR gets a
  doorbell — verdict, the blocking findings, a link — enforced by a linter, not
  by asking a model to be brief. A clean approve is one line. The linter blocks
  a comment carrying a credential outright and never echoes what it caught, so
  the natural output of a good security finding cannot publish the key it just
  found to a public thread.
- **`docs/research/`** — the sourced research behind the review rebuild: how
  Anthropic's and gstack's reviewers are tuned, what three review vendors claim
  and what survived checking, and why the recall-max stance was abandoned.
  Reference material for the next person to change the skill; nothing loads it
  at runtime.
- **`references/review-preflight.md`** — what the deterministic pre-flight
  establishes before any model judges anything, and how to read the three
  statuses that are gaps rather than passes.

- **Auto-capture now tells you whether semantic dedup actually ran.** The
  near-duplicate lookup runs under a deadline, and a killed query returns
  nothing — which reads exactly like "no duplicate found". Each capture now
  reports `ran-clean`, `ran-timeout`, `ran-error`, or why it did not run, so a
  hung index shows up instead of quietly costing you deduplication.
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
