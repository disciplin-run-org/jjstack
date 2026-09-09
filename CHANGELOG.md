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
- **Destructive commands you actually want are now approved.** A blanket
  denylist refused ordinary work: deleting one named build directory,
  resetting one named branch, force-pushing one named feature branch. The
  rule is now that a destructive command passes when it is **specific** —
  it names a definite target rather than sweeping a broad root — **and
  matches its stated purpose**. "Remove the stale build directory" justifies
  deleting that directory; it does not justify deleting a source tree.
- **Two deterministic rules bracket that judgement**, so a model's opinion is
  never the only thing between you and an unrecoverable act. A **floor** no
  rating can lift refuses unbounded reach (a filesystem root, a bare `$HOME`
  or `~`), unreviewable content (`curl … | sh`), uploading a local file or
  naming a known secret path, device writes, fork bombs and power commands.
  And because alignment cannot be judged against a purpose nobody stated, a
  destructive command carrying **no description defers** — the same command
  with a purpose is approved.
- **Two holes in the previous release's gate are closed.** `rm -rf ~` slipped
  through (the rule required `~/` with a slash), and so did `curl -d @` with
  a credential file (only curl piped to a shell was caught). Both had been
  reported as refused — they were, but by the model's rating rather than by
  the deterministic floor, so the floor was never actually holding them.
  Both are now on the floor, with fixtures.
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
