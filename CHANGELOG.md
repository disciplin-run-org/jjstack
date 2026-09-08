# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Fixed

- **`/review` can no longer publish a credential to a public pull request.**
  The review's security lens is the thing that finds a leaked key, and the
  comment style it writes findings in puts the evidence on the line: `**P0**
  conf.py:12 AWS key committed: AKIA...`. That comment was posted. Deleting it
  afterwards does not help - GitHub keeps every edit of a comment, and the
  original body stays readable. The pre-post check now refuses outright on a
  credential of any recognised shape (AWS, GitHub, OpenAI-style, Slack, Stripe,
  Google, a JWT, a private-key block, a password inside a connection string).
  It cannot be silenced with `--quiet`, it has its own exit code, and it never
  prints the value it caught. The finding keeps its evidence in the committed
  report; the comment cites `file:line` and nothing more.
- **The comment budget no longer passes a comment it could not measure.**
  Passing an empty or non-numeric `--max-lines` made the size check
  unevaluatable, and an unevaluatable check counted as a pass: a 41-line comment
  against a 12-line budget was reported clean. Bad budget values are now a usage
  error before anything is measured. A check that cannot run is not a check that
  passed.
- **The three-finding cap now counts findings, not lines.** Five findings
  written on one physical line counted as one, so the comment passed. It also
  now recognises a severity however it is written - `**P0**`, `[P0]`, `(P0)`,
  `"P0"`, `Critical:`, `[Major]` - instead of the handful of decorations it had
  been taught. The same count decides whether a comment is a clean approve, so
  an approve carrying unrecognised findings used to be waved through twice over.
- **A link to a report that does not exist is no longer accepted as a link.**
  The rule that stops "be brief" turning into "drop findings" was satisfied by
  any URL inside a finding's own citation, and never checked that a named report
  file was really there. It now looks for the report on disk.
- **A review comment must now declare what it is not showing.** "N blocking, M
  total" was a style suggestion in prose; a comment could show three findings,
  declare no total, and pass. The count is now checked, including the
  arithmetic: seven found and two shown has to say "5 more" and link the rest.
- **`/review` no longer reads a GitHub outage as "this branch has no PR".** An
  expired token, a rate limit or a DNS failure all produced the same silent "no
  pull request" outcome as a branch that genuinely has none, so a review could
  fail to post and tell nobody. The two are now reported separately. The PR is
  also resolved once and the post is bound to that number and repository, rather
  than re-derived from the branch - which is nothing at all in the detached-HEAD
  worktree `/review` often runs in.

- **"I disproved it" now has to show the document.** `/review` can retire a
  finding by checking it against the library's current official docs — the
  usual cure for a reviewer complaining about an API that changed years ago.
  That outcome used to need nothing but a label: two words, no link, and the
  most serious class of finding vanished from the report, under a heading
  that told you it had been "disproved against current official docs". The
  documentation link is now required. Without one the run stops and prints
  nothing, so a review can no longer quietly delete its own worst finding.
- **The same review now produces the same report.** When two passes flagged
  one defect and disagreed about what to do with it, which decision survived
  depended on which line happened to be written first — the identical review
  could file a finding as "refuted" or as "suppressed" on two different runs,
  and in neither case did it mention that it had collapsed the two. Reviews
  are now a function of what was found, not of the order it was found in, and
  a collapse that changes a finding's severity or its outcome is always listed.
- **The dependency inventory stopped losing most of your dependencies.** The
  list `/review` reads to check library versions is parsed from your
  manifests, and several very ordinary spellings were dropped in silence: a
  Python extra like `celery[redis]` truncated the rest of the list at that
  line, Poetry's dependency groups and its older `dev-dependencies` section
  produced nothing at all, Rust dependencies written with their own
  `[dependencies.<name>]` block disappeared, and a Maven dependency written
  on one line was skipped entirely. All of them are read now, Ruby and Java
  manifests have real coverage for the first time, and the output is checked
  to be well-formed before anything consumes it — including for project paths
  containing characters that used to corrupt it.
- **The auto-fix review pass no longer reports your own scratch files back at
  you.** Post-pass 2 takes a marker before the review is allowed to change
  anything, so it can tell the reviewer's edits from work you already had open.
  The marker covered files git was already tracking, but not brand-new files you
  had not committed yet — so a note you wrote before the review still turned up
  in the report as something the reviewer had created, under a header saying the
  marker had been taken first. The marker now records untracked files too, and
  lists them in three honest groups: created by the review, already there and
  changed since, already there and now deleted. Files you had and nobody touched
  no longer appear at all, and a run where the review changed nothing now says
  so instead of listing your work in progress.
- **The calibration report is actually ranked.** `jjstack-review-calibration
  report` prints your accepted/rejected patterns with a rank, and the rows are
  meant to be ordered by it. They were not: the plus sign in `+20` defeated the
  sort, so every positive rank tied and the ranked view came out in effectively
  arbitrary order. Rows are now ordered by rank, ties broken by pattern name, so
  two runs over an unchanged ledger print the same thing.
- **The post-fix sweep no longer skips your npm checks when the project lives in
  a folder with an apostrophe in its name.** Reading `package.json` treated the
  folder's path as part of a program rather than as text. A path like
  `/home/you/it's a repo` broke that program, the error was hidden, and every
  `npm run lint` / `npm run test` check quietly vanished from the plan — the
  sweep then reported on what was left without mentioning what it had dropped.
  The path is now passed as data, and a folder name can no longer influence what
  the sweep runs.
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
  stable — and it no longer waits on the network at all.

- **A gbrain lookup that failed no longer claims it ran clean.** The dry-run's
  dedup report used to say `ran-clean` — "semantic dedup ran and found no
  duplicate" — whenever the lookup did anything other than time out. A corrupt
  or unreadable index, a gbrain binary that had been moved, or a bad deadline
  value all produce the same empty result as a genuine no-match, so the run
  reported success while doing nothing. Those cases now report
  `ran-error:<code>` and their empty answer is discarded rather than believed.
  `ran-clean` again means only what it says.

- **Capture now tells you whether dedup ran when it actually matters.** The
  report naming which duplicate-detection layers ran — and why one didn't —
  used to appear only under `--dry-run`. The real capture path, the background
  worker that runs when a session ends, said nothing. That is precisely where a
  hung or broken gbrain quietly costs you deduplication, with nobody watching.
  Every capture now prints the same one-line state.

- **The test suite no longer reads or writes your real memory.** Running
  `test/smoke.sh` used to point parts of itself at your actual memory store,
  your actual gstack learnings and this checkout's git remote. Three
  consequences, all bad: the background capture worker could change the store
  mid-run and turn a passing suite red; a failure on one machine could not be
  reproduced on another; and one guard was watching a directory the run never
  touched, so it passed whether the code worked or not. The whole suite now
  runs against a throwaway home directory and throwaway fixture projects,
  removed when it exits, and it lints itself so a future test cannot quietly
  reach back out.

- **The gbrain lookup deadline is documented and adjustable.**
  `JJSTACK_CAPTURE_GBRAIN_TIMEOUT=<seconds>` (default 8) sets how long capture
  waits for the semantic dedup query. On a slow link or a large index, raise it
  instead of turning dedup off entirely — previously the only documented remedy
  was `JJSTACK_CAPTURE_NO_GBRAIN=1`, which removes the layer altogether.

### Changed

- **`/review`'s memory of your team's decisions now lives in one place, in one
  format — and `/review` is 1.0.** Everything `/review` remembers about a
  finding is now under `jjstack/review-memory/` in your repo, as three
  tab-separated files instead of a JSON file at the repo root, a Markdown file,
  and a TSV. The version was deliberately held at 0.4.0 until this landed,
  because the public contract of this skill is its script CLIs and its store
  formats, and this is the change that settles them.

  **They stay three files on purpose.** They are a ladder, and the rung is set
  by how specific the memory is:

  | what it remembers | strongest thing it can do |
  |---|---|
  | "we generally don't care about this **pattern**" | rank it lower in the report |
  | "we dismissed this **category in these files**" | file it under *Demoted*, still active |
  | "we accepted **this exact finding**" | take it out of the active set |

  Only the last one can silence anything, and only with a written reason. That
  is what stops a broad, half-remembered preference from quietly burying a real
  P0 — and it is enforced by the tools, not by good intentions, on all three
  rungs, when the record is written AND again every time it is read. A
  wide-scope record that claims a suppression is rejected outright, and so is a
  record that would act on your findings with any verdict other than the one its
  rung is for — including a verdict that is too WEAK, because a dismissal
  recorded as "changes nothing" was still demoting.

  A dismissal must name a place, too: a path pattern made only of wildcards
  matches your whole repo, so it is refused when it is written and on every row
  every time the store is read — including the rows the migration below
  produces.

  **Why TSV for all three:** the value of these files is their diff. One
  decision is one line, so accepting a finding shows up in a pull request as a
  one-line addition, retiring it as a one-line deletion, and `grep` finds
  either. JSON hid that; Markdown made it unparseable for the tools.

  **Migrating is a one-time, explicit step.** If you have used `/review` before,
  the tools will stop and tell you to run
  `bin/jjstack-review-memory-migrate --repo <your repo>` once. Read the new
  files, delete the old ones, commit both together. Nothing migrates itself:
  these files are version controlled, and a tool that rewrote one behind your
  back would produce a diff nobody approved. And the migration cannot let
  anything through that the stores themselves would refuse: every converted file
  is handed to the validator of the tool that owns it, and only what passes is
  installed. If a legacy row will not convert — a repo-wide `*` pattern, say —
  the conversion is left beside its destination as `<store>.rejected` for you to
  read, the legacy file stays put, and you are not told to delete it. Notes
  containing a `|` now survive the move whole, instead of being cut at the first
  pipe.

- **The per-run triage ledger is now called the run report.**
  `bin/jjstack-review-triage` is `bin/jjstack-review-run-report`, and its output
  is `review-run-report.md`. It was never memory — it is the audit trail of one
  review run, regenerated every run — but its old name and file were confusing
  enough that four separate changes treated it as a fourth memory store. It now
  refuses to run against a memory file at all. If you scripted the old name,
  update it.

- **One list of reason codes across the whole of `/review`.** The closed
  vocabulary that explains why a finding was demoted, deferred or suppressed now
  lives in a single file (`bin/jjstack-review-vocab.tsv`) read by the run report
  and all three memory stores. Each code also declares the strongest verdict it
  may carry, so a rule like "unreachable code is deprioritised, never deleted"
  is now one line of data enforced in four places instead of a comment enforced
  in one.

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

- **`/review`'s dependency inventory no longer loses your runtime dependencies.**
  A `package.json` written on one line — the form npm, bundlers and code
  generators emit — had every dependency group but the last silently discarded.
  The inventory reported success with `react` missing, and every stale-API
  finding about the dropped library was then treated as "unknown library" and
  quietly downgraded. It also died outright on a checkout path containing a `#`
  (`build#42` and friends are ordinary in CI), producing an empty inventory, and
  it hung at 100% CPU forever if you typed `--depth` without a number.

- **`/review` can no longer read a broken dependency scan as "no dependencies".**
  "This repo declares nothing external" and "the scan found manifests but parsed
  none of them" used to share one exit code, and the review was told the first
  one is normal — so a parser failure read as a clean bill of health. They are
  now distinct, and a parse failure is reported as a problem to fix rather than
  skipped past.

- **A review finding disproved by the docs is now on the record instead of just
  gone.** `/review` looks up current official documentation before believing its
  own "you're using this library wrong" findings, and drops the ones the docs
  refute. That drop had nowhere to be written down: the triage ledger's
  vocabulary had no code for it, so the finding simply left the report — the
  exact disappearing act the ledger exists to prevent. Refuted findings now
  appear in their own ledger section with the documentation link that settled
  them. Those lookups are also capped and deduplicated per library, so a review
  with thirty findings across five libraries makes five searches, not thirty.

### Added

- **`/review` now posts its verdict on the pull request, in your voice, in about
  six seconds of reading.** Until now the review wrote a thorough report into
  `{repo}/jjstack/` and stopped: a report nobody opens is a review that did not
  happen. The verdict now lands as a PR comment.

  The comment is a doorbell, not the delivery. Verdict line, the findings that
  actually block the merge, and a link to the full report - which still holds
  every finding, every repro, every confidence score. Brevity moves evidence, it
  never deletes it: a finding cut from the comment is a finding still in the
  report, and cutting one to fit the budget is refused outright.

  The budget is enforced by code, not by asking. Twelve lines, 900 characters, at
  most three findings inline, and a link is mandatory. "Be brief" written as a
  prose instruction loses to a model's pull toward completeness on every single
  run, so `jjstack-pr-comment-lint` blocks the post instead of hoping. It also
  enforces the voice: no emdash, no superlatives selling a finding, no
  meta-commentary, no softening qualifiers, no sentence too long to survive as a
  tweet.

  The jj in jjstack is Jesper Jurcenoks, and a review posted under this name
  sounds like he wrote it: conclusion first, one line per finding, and a
  correction framed as "this is my concern" rather than "you are wrong". The
  review-scoped voice ships in `references/pr-comment-voice.md`; point
  `dna.voice` at a fuller voice file to layer it on top.

  No pull request is a normal outcome, not an error: the review says so and stops
  rather than inventing one.

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
- **`/review` now does five things after it finishes reviewing.** A review that
  has read the diff from every angle still hasn't asked five questions, because
  none of them are questions about the diff's contents:
  1. **What should have changed and didn't.** A schema change with no migration,
     an enum member whose `switch` statements weren't updated, a signature change
     that missed a caller, a new config key with no default, a new error case
     with no handler. Nothing that reads a diff can see what isn't in it, so
     these normally reach production untouched by review.
  2. **A review of the fixes the reviewer applied itself.** The review step that
     auto-applies safe fixes writes real code that no reviewer has ever looked
     at — it arrives blended into your branch under the banner of a completed
     review. It is now pulled out as its own diff and reviewed as if a stranger
     wrote it. `/review` takes a snapshot of your tree *before* it is allowed to
     change anything, so this pass shows you only the reviewer's edits — your own
     work in progress is never handed back to you as someone else's bug.
  3. **A failing test for each serious finding.** Instead of asserting a bug
     exists, `/review` writes the test that goes red and runs it, and you get
     that regression test along with the report. If the test comes out green the
     finding is *not* deleted: it moves to a "Disproven by test" section with the
     test attached, because a green test can equally mean the test is wrong — and
     that call is yours, not the reviewer's.
  4. **Your typechecker, linter and tests re-run after the fixes land.** The
     cheapest, most certain reviewer you own, pointed at the post-fix code. This
     is what catches a fix that broke the build or turned a green test red. If
     your project has a linter but no test runner, this pass now says **PARTIAL**
     and names what it couldn't check, instead of reporting "clean" on the
     strength of the linter alone.
  5. **Memory of what you accepted and rejected.** Verdicts are recorded in your
     repo (`jjstack/review-calibration.tsv`), and the next review uses them to
     ORDER its report — a class you have dismissed twice is ranked down the page
     under a section that says so, a class you keep confirming is ranked up.
     Nothing is removed and no confidence score is touched: the score is a claim
     about your code, the demotion is a claim about your past decision, and only
     the baseline (with a reason you wrote) takes anything off the active list.
     Previously every review started from zero and re-guessed.

  Any of the five that doesn't apply to your project — no test runner, no
  auto-fixes, no history yet — is reported as SKIPPED with the reason, never
  quietly passed off as clean.
- **`/review` now shows you what it decided NOT to tell you.** Every finding the
  review raises — including the ones it judges too weak, too nitpicky, or
  already covered by your linter — is written to a triage ledger next to the
  report, each with a recorded reason for its fate. Previously a low-confidence
  finding just vanished, and there was no way to tell a reviewer that looked and
  dismissed from one that never looked. Three rules are now machine-enforced and
  the review will refuse to render a ledger that breaks them: nothing is dropped
  without a stated reason; "this code isn't reachable" can lower a finding's
  priority but can never delete it (unreachable today is reachable after the
  next refactor); and a P0 or P1 can be deferred but never made to disappear.
  The ledger also collapses duplicates — the same defect found by three
  different passes becomes one finding that shows it was flagged three times,
  which is now a ranking signal — and labels each finding's blast radius
  (production code vs test, fixture, vendored or generated), so a warning about
  a test fixture is visibly a warning about a test fixture.
  Collapsing duplicates never costs you a finding: when two genuinely different
  problems land on the same line, both sentences stay on the page — each with
  its own severity and confidence — and the collapse is listed in the ledger's
  Merges section. Previously the second one silently disappeared while the
  count still said one finding.
- **`references/vendor-lessons-aikido.md`** — what a commercial security-scanning
  vendor's AI triage actually does, what we took from it, and (with sources) the
  claims we rejected as marketing.

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
  A finding you previously dismissed drops to the report's "Demoted (prior
  decision)" section with your own note quoted as the reason, keeping its
  severity and score — it is **demoted, never dropped**, so you can always
  see what was set aside and why. Security, correctness, concurrency,
  error-handling, resource-leak and test-coverage findings never demote at all,
  however many times they were waved off; those are the classes where a wrong
  suppression ships an incident. And unlike the hosted tools this idea came from,
  the memory is a plain file in git: a suppression is reviewable in a PR, and
  retiring one is a visible diff instead of a setting nobody can audit.
  A dismissal has to name a *place* — `src/legacy/*`, not `*` — so one line can
  never quietly go repo-wide. That is enforced on what the pattern *matches*,
  not on how it is written: `*`, `*/*`, `*[a-z]*`, `[a-z]*` and `*.*` are all
  the same blanket and are all refused, and the same test is applied to rows
  read back out of the file, so a blanket line that arrives by hand-edit or by
  merge is ignored with a warning rather than quietly demoting your whole repo.
  A note is quoted back to you whole — pipes, line breaks and all; it can never
  spill onto a second line or forge a ledger row of its own. The repo column
  names the repo the *ledger* belongs to, so a ledger copied between projects
  still says what it is about. And if the ledger file is missing or misspelt,
  `/review` tells you it did not read one instead of reporting a confident
  "nothing was previously decided".
- **`/review` says when it could not actually look.** On a shallow clone — what
  CI gives you by default — there is no history to search, so the revert-history
  pass now reports the window as truncated and tells you to treat the git-history
  check as *not run*. It used to print "no revert or rollback history on any
  changed file", which reads as a clean bill of health for a search that never
  happened.
- **`references/vendor-lessons-greptile.md`** — the homework behind the above.
  What Greptile's reviewer verifiably does, which of its claims are real
  mechanics and which are unfalsifiable marketing (their headline benchmark
  scores bugs caught while *excluding false positives from scoring*, so it
  measures recall only), and an explicit list of what jjstack adopted, what it
  rejected, and why. Useful on its own if you are evaluating AI review tools.
- **`/review` now looks outside the diff, and stops flagging code that is
  actually correct.** Two additions, both aimed at bug classes a diff-only
  reviewer cannot reach:
  - **The caller nobody updated.** When a change alters a function's signature,
    return contract or error behaviour, the resulting bug isn't in the diff — it
    is in the files that call it and were left alone. `/review` now lists, for
    every definition the change touched, which files reference it and which of
    those the diff never opened, and goes and checks them. That list is the
    review's map to a defect it previously had no way to see.
  - **Stale-knowledge false alarms.** An AI reviewer judges your library calls
    against the version it saw in training. When the library has moved on,
    correct code gets reported as broken — one of the most common ways an AI
    review wastes your time. `/review` now reads the versions your repo actually
    pins (npm, Python, Go, Cargo, RubyGems, Maven) and checks any "you're using
    this API wrong" finding against the real documentation for *that* version
    before showing it to you. Findings that survive arrive with a doc link;
    findings that don't are dropped as what they were — the reviewer
    misremembering. This is the rare filter that costs you nothing: it removes
    findings that are wrong, never findings that are merely minor.
- **`references/vendor-lessons-macroscope.md`** — the research behind the above:
  what Macroscope's AI reviewer does, which of its claims stand up, and which do
  not. Includes the working: their headline "2X more bugs than Greptile" rests on
  a benchmark their own methodology page shows was run on unequal samples after
  the competitor's access was cut off mid-evaluation. Written so you can see what
  was rejected and why, not just what was adopted.
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
