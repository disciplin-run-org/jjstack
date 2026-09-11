# Changelog

All notable, user-facing changes to jjstack are recorded here. This is a
high-level summary for people who USE jjstack — what's new or different and
why it matters — not a commit log. For commit-level detail, read the git
history.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added

- **`/review-lean`: the same review, rebuilt clean.** `/review` grew by
  patches over a dozen review rounds. `/review-lean` is the production build:
  the same budgets, verdicts, GitHub review, commit status and gates before
  posting, in 469 lines instead of 740. The incident stories are gone from its
  instructions, because the tests that guard against those incidents already
  hold them. Both skills now share one test contract, so the rules and
  commands it pins cannot drift apart. Run it with `/review-lean`; `/review` is unchanged and stays the
  default until the swap. Its comments open with
  `Claude jjstack/skills/review-lean/SKILL.md` and its status check is
  `jjstack/review-lean`, so you can always tell which of the two wrote a
  verdict.

- **Review requests now open their own review session.** Start
  `jjstack-review-daemon` in the reviewer directory and leave it running.
  When someone requests a review from `ai-assistant-2026`, or someone with
  write access @-mentions it on a pull request, the daemon opens a new window with a worker session named
  after that PR. It checks the session is running on Opus, then sends it
  `/review`. When the author fixes things and re-requests, the next round goes
  to the same session, so it remembers the last one. When the PR is merged or
  closed, the session saves its lessons and exits on its own. Requests from
  repositories you do not own are ignored, and so is a mention from anyone
  without write access, so nobody else can use the reviewer for free. Four sessions run at once at most; the rest wait their turn. This
  replaces typing `claude-tm --role=...` and `/review ...` by hand for every
  pull request. `/review-daemon` explains how to start and check it.

### Fixed

- **The review daemon counts a mention only where GitHub shows one.** It now
  reads the comment as GitHub renders it. A handle inside backticks or a
  code block no longer starts a review round, so a comment that only talks
  about `@ai-assistant-2026` stays a comment. A real mention written in the
  browser, below a code block, is no longer missed. When GitHub cannot say
  whether the person who mentioned the reviewer has write access, the
  daemon asks again on its next poll instead of dropping the request. It
  still opens nothing until the answer is yes.

- **A re-run can no longer post on the previous round's answer.** When a round
  is voided because the author pushed, the answer that voided it names the new
  head — which is exactly the head the re-run is about to review. So a re-run
  that skipped the head check would have posted on that stale answer, although
  the skill said a skipped check refuses. Resolving the pull request now
  discards the previous answer in the same step, so the only way to post again
  is to ask again.

- **New versions are announced again, for installs that are git clones.**
  Since branch protection went on for independent review, every merge to main
  failed to release: the release step committed a version bump straight to
  main, main refused it, and the version every install compares against stayed
  at 0.42.0 through six merged changes. So nobody was told there was anything
  to upgrade to. A release is now a tag on the merged commit, which needs no
  commit to main at all, and the update check, `jjstack-upgrade`,
  `jjstack-skills-pin --status` and `/jjstack-repair` read the version from
  that tag.

  `VERSION` stays on main, frozen at 0.44.0, for one reason: an install that
  has not upgraded yet still runs the old check, which reads that file, and
  the upgrade it announces is the only way that install gets the new check.
  Nothing reads it after that. A tarball install, one that is not a git clone,
  is told about this upgrade once and about no release after it, because it
  has no tags to compare. Replace it with a clone to keep being told.

- **A dollar amount in a skill no longer turns into your second word.** The
  skill loader replaces `$0`, `$1` and so on with the words you typed after the
  command, before the model reads the file, and it does so inside code blocks
  too. `/consensus` wrote its costs as `~$0` and `$10`, so a run titled itself
  after your first word and its verdict said `Cost: ~Stance:`. The four sites
  are reworded (a contributed fix), and the skill verifier now refuses any
  skill body carrying such a token, so the next occurrence fails on the pull
  request rather than in your session. An argument a skill really means is
  written `$ARGUMENTS[N]`, which the verifier leaves alone.
- **Four checks that could not have failed.** The change that split the session
  verbs added guards to keep them split, and review found that several of them
  were reading text that had never existed in the form they searched for. A
  check anchored on one line cannot see a call written across two, and that is
  how these files write a call. Each one now carries a copy of the real defect
  it exists to catch, taken from the repository's own history, so a check that
  stops working says so instead of passing quietly.

  Nothing about how the verbs behave has changed. What changed is whether the
  machinery that keeps them honest is honest itself.

### Changed

- **Clearing your context no longer picks the old task back up.** There are
  three things you can want at the end of a session, and until now two of them
  ran the same machinery. `/save-and-clear` filed a resume order whenever the
  work "continued" — true of almost any session mid-task — so asking for a
  clean slate to start something new produced a successor that resumed what
  you had just walked away from.

  The three verbs now do three different things, and you pick by what happens
  next rather than by how full the context is:

  | You want to | Use | It hands the next session |
  |---|---|---|
  | Shut down, keep the lessons | `/save-and-exit` | nothing |
  | Start a different task, keep the lessons | `/save-and-clear` | nothing |
  | Keep going on THIS work in a fresh context | `/rollover` | the handover |

  All three still sweep the conversation for durable lessons and write them to
  memory. That part never depended on which one you picked. The first two now
  also close out your Quartermaster items instead of leaving them in flight
  against a session that no longer exists, which used to stall that worker's
  queue until someone noticed.

  `/rollover` is a skill in its own right now rather than a variant of
  `/save-and-clear`, and it writes the handover to a file that the next
  session reads and then retires. That file is what makes the difference
  concrete: no handover, no resume. Roll over outside a tubemail worker and
  you are told exactly what to type; type something else first and your next
  session is reminded that a handover is waiting for it.

  There was a second route by which the old work came back, and it is closed
  too. A worker that restarts with a fresh context reads its own message
  timeline to catch up, and with no memory to check against it could not tell
  a finished order from an unanswered one, so it re-ran them. All three verbs
  now mark the timeline as settled before they close, and a fresh session
  reads only what arrived after that mark.

- **The skills every session loads no longer follow your checked-out branch.**
  `~/.claude/skills/jjstack` used to be a shortcut straight into the jjstack
  clone you develop in, so whatever branch that clone sat on was what every
  Claude Code session on the machine executed, and a file saved mid-edit was
  the live skill. `./setup` now points it at a pinned copy in
  `~/.jjstack/skills-pin` that only moves when you move it, with
  `bin/jjstack-skills-pin` to move it and `--status` to see what is live.
  `jjstack-upgrade` advances it after a pull, so upgrading works as before.

  What changes about developing: a skill edit is live once you commit it and
  re-pin (`bin/jjstack-skills-pin HEAD` to serve your branch on purpose,
  `bin/jjstack-skills-pin` to put the release back). That is a step you did not
  have before, and it is the price of the machine not following your working
  tree by accident. Hooks have been installed this
  way since the permission gate landed, for the same reason; this is the
  skills half of that. Installed from a tarball rather than a clone, setup
  serves the directory directly and tells you so.

  This is not hypothetical. An in-flight pull request branch was this
  machine's `/review` for hours, and the reviewer of that very pull request
  had to pin a copy by hand before its verdict could say which version of the
  reviewer produced it.

### Fixed

- **A review can no longer be published against code that has since changed.**
  Every finding in a round is measured against one commit. If the author pushes
  while the round runs, the report describes code that is no longer there — and
  nothing checked. Two rounds on this repo were published that way. `/review` now
  asks GitHub what the pull request head is before it posts, compares it to the
  sha the round started from, and refuses to publish a stale report instead of
  hand-patching it. Before the round starts it also checks that the tree being
  read is that commit, so a tree left over from an earlier round cannot be
  reviewed under a newer head's name. If it cannot find out — no network, a
  token without access — it says so, rather than telling you the author pushed
  and sending the reviewer round the loop again.

  The check asks GitHub about the pull request itself, not about a branch in a
  local clone, because the obvious local shortcuts answer a different question:
  a fork's branch does not exist in your clone at all, and `FETCH_HEAD` is
  overwritten by the next fetch of anything. It also means the check works from
  the reviewer's own directory, which is not a clone of anything.

- **The reviewer's checkout is written down.** The independent reviewer runs
  from its own directory and holds no clone of the repo it reviews, so every
  round has to materialise the pull request head and then remove it. That was being
  retyped from memory, which is why stale worktrees accumulated from rounds that
  had ended weeks earlier. `references/independent-review.md` now carries the
  commands, and `/review` points at them when it starts with no tree to work
  from, so the procedure is reachable from the skill rather than only from the
  reference.

- **`/receiving-code-review` refuses to merge a pull request with something
  unread on it.** GitHub's "mergeable" answers whether the branches conflict,
  not whether anyone has reviewed you, and a review that lands in the gap
  between that check and the merge ships unread. Not hypothetical: a review of
  this repo posted three blocking findings nine minutes before the pull request
  was merged on a mergeability check read before the review existed, and all
  three shipped in a release. A new `jjstack-pr-unread-check` exits non-zero
  when the thread has moved since you last read it, and the merge is chained
  behind it, so it cannot run past. It reads all three surfaces a person can
  leave something on - an issue comment, a submitted review, and a reply inside
  an inline review thread - because they are three different shapes and the
  usual tools return only the first two, and it treats a thread it could not
  read as a refusal rather than as good news.
- **A review comment can no longer approve at the top while rejecting at the
  bottom.** Now that the report rides inside the comment, the visible verdict
  is checked against it: a one-line "all issues resolved - lgtm - approved"
  sitting over a report that rejects is refused, and a declared finding total
  smaller than the report beneath it is refused too. Before this, the reader
  saw the approval, merged, and the blocking findings sat one click below,
  unread.
- **Two routine credential shapes are caught.** A bearer token written after a
  word (`Authorization: Bearer …`) and a URL whose password has no username
  before it both published clean. Quoting the offending line is what a security
  finding is supposed to do, so finding the hardcoded token had become the act
  that published it.
- **Pointing the comment assembler's `--out` at one of its own inputs no longer
  destroys that file.** It truncated before reading and exited zero. The report
  is a working file that is never committed, so one mistyped flag at the end of
  an hour cost the hour and the tool reported success.

### Changed

- **"Done" now means someone else reviewed it.** The Definition of Done has an
  eleventh rung: before a pull request is merged, a Claude Code session that did
  not write the code reviews it and approves it on GitHub. The reporting form is
  now "done N/11". Until now every review on this repo was run by the session
  that wrote the change, and eight merged pull requests in a row carried no
  review at all.

  Review is a loop, not one gate. Every push that answers findings gets a fresh
  review request, and the merge waits for an approval newer than the last
  commit. An approval from the round that asked for the changes does not cover
  the changes it asked for.

  Who must approve depends on whose repository it is. On InboundSavvy
  repositories the AI review goes first and then Andre or Santiago is asked, so
  they see a converged change rather than a draft. On disciplin.run and personal
  repositories one AI review is enough. The table, the protocol for both sides,
  and the branch-protection settings are in `references/independent-review.md`,
  including the two commands that repeatedly went wrong by hand: requesting a
  reviewer over REST, because `gh pr edit --add-reviewer` fails whole against a
  repo with Projects classic retired, and turning on
  `require_code_owner_reviews`, without which a `CODEOWNERS` file is requested
  but never required.

  A review you run on your own pull request still runs and is still worth
  running before you hand it over. It just does not satisfy the rung, and
  `/review` now says so in its close-out instead of leaving you to notice the
  missing green check. Branch protection requiring an approval is set per repo
  once the reviewer account has approved something there; it is not on yet.

- **The README now says where the review runs.** Rung 4 said who reviews your
  code; it did not say that the reviewer is a session in a different directory,
  with its own credentials and no clone of the repo it is reviewing. That is what
  buys the distance — what the reviewer holds is a copy of your head, not your
  branch, and it does not push, so a finding has to be written down and argued
  for rather than quietly fixed — and it is why your own tree is never touched
  and why you can carry on with the next thing while the round runs beside you.

  It also settles the alternative that was proposed and rejected: a command that
  spawned a second reviewing session from your own. A session spawned that way
  inherits your GitHub identity, so it can never post the review rung 4 waits on.

- **Long-running work no longer stops to ask you for permission.** Over a
  measured 48 hours, sessions on this machine interrupted a person 430 times,
  about nine times an hour, and every single interruption was approved. That
  is not a safety check, it is a queue of things you have to click. Two causes,
  both now gone. The permission settings listed the verbs an autonomous run
  uses most (`rm`, `curl`, `git push`, `sudo`, `chmod -R`) as "always ask", and
  an always-ask rule interrupts you in *every* mode — including a session you
  deliberately started with permission checks skipped, which is why that flag
  never seemed to work. And the gate itself asked a small model to rate each
  command, then woke you whenever the answer came back unreadable, which it
  did four times out of ten on long commands.

  In their place is a gate that decides on its own and never asks. It refuses
  ten kinds of command outright: ones whose reach has no bound (deleting a home
  directory or a filesystem root), ones running code nobody has read (piping a
  download into a shell), ones sending a local file or a known secret to the
  network, ones writing to a raw disk, ones powering the machine off, and
  force-pushes to the trunk. A refusal tells Claude the rule and the fix, so it
  tries another way in the same breath rather than parking the job until you
  come back. Everything else simply runs.

- **Claude is now held to one command per Bash call.** Chaining several
  commands into one call is refused with instructions to split it. That has
  been the house rule for months and it was quietly ignored: 391 of the 393
  commands that interrupted somebody were chained. It matters for more than
  tidiness. A call that starts `S=/tmp/x; rm -rf $S` hides the `rm` behind an
  assignment, so no safety rule and no audit report ever sees it, and the log
  of what was actually run becomes unreadable. Writing a multi-line file or a
  commit message still counts as one command.

- **What the permission gate is doing is now something you can look at.**
  `bin/jjstack-permission-audit --since 24h` reports how often anyone was
  interrupted, by which session, and for what, plus how much of the work is
  still chained. Run it after a long unattended session; the expected answer
  is zero.

- **jjstack's hooks are installed as copies instead of shortcuts into the
  source folder.** The permission gate used to be a link into the working
  copy, which meant that switching branches in that folder silently changed
  what every Claude session on the machine was allowed to do. Installing now
  writes real files, replaces any old link, and backs up your settings first.

- **`/security-review` is now `/jj-security-review`, and shadowing a Claude
  Code built-in is a declared, checked decision.** Claude Code ships its own
  `/security-review` and `/review`. jjstack's skills sat on both names, so
  typing them reached jjstack's and, for `/security-review`, Claude's had no
  other name to be reached by. The rule now: jjstack shadows gstack names by
  design, shadows a Claude Code name only when the built-in keeps another
  name and the skill says so (`/review` does — Claude's reviewer is
  `/code-review`), and otherwise takes the `jj-` prefix. Re-run `./setup`:
  it removes the old `security-review` link. `bin/jjstack-verify-skills`
  fails on an undeclared collision or a stale declaration, reads the
  built-in list from `references/claude-code-builtins.txt` (regenerate with
  `bin/jjstack-builtins-refresh`), warns when your Claude Code is newer than
  that list, and runs on every pull request — before this, nothing ran it.

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

- **`/review` now posts its verdict as a GitHub review, not a loose comment,
  and looks at what the change is rather than only whether it works.** The
  verdict used to arrive as an ordinary comment, which left the PR's Reviews
  box empty: GitHub recorded the pull request as never reviewed, and a branch
  rule that requires an approval saw nothing. It is now a review, with the
  verdict mapped to approve, comment, or request-changes. On a pull request
  you opened yourself GitHub refuses to record a state at all, so the review
  posts as a comment there and the closing line tells you the state was
  refused instead of implying a green check. Requesting a reviewer has its
  own two traps, both now documented with the call that actually works.
  A re-review reads the previous round from both channels, picks the newest
  one by timestamp rather than by which channel it came from, and accepts
  only rounds this account actually posted: the body's attribution line is a
  prefix anyone can type, while authorship is attested by GitHub.

  The review also gained the questions it was missing. It asks whether the
  change is the right shape and whether it is more complex than the problem
  needs, reads names and whether comments say why rather than what, names any
  file in the diff that no pass opened instead of reporting a coverage
  fraction that counts only passes, and may name one thing the change does
  well.

  It also says when it has started. GitHub has no "under review" state, and
  the thing that looks like one, a review left unsubmitted, is visible only
  to the person who started it. `/review` now posts a pending commit status
  when it begins and replaces it with the verdict when it ends, so everyone
  can see a review is in flight and a repository can require that check
  before a merge. On a pull request you opened yourself, where GitHub refuses
  to record an approval, that status is the only machine-readable verdict
  that works.

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
