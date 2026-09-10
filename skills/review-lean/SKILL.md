---
name: review-lean
version: 0.1.0
description: |
  The production build of /review: the same pre-landing review, held to the
  same smoke-test contract in far fewer lines. Runs side by side with /review
  until it replaces it (Claude Code's own reviewer is /code-review).
  Deterministic pre-flight (the repo's own typechecker, linter and tests, the
  callers outside the diff, the stated intent), four bounded passes, verified
  findings, and an APPROVE/CAUTION/REJECT verdict posted as a GitHub review
  with the full report collapsed beneath it. Budgets: 60 min, 4 agents, 10
  findings. Re-reviews report only regressions and new P0/P1.
  Trigger on: "/review-lean", "review-lean", "lean review". Do NOT trigger
  for a plain "review this PR" (that is /review until the swap), security-only
  review (/jj-security-review), spec-then-quality review (/two-stage-review),
  or answering review feedback (/receiving-code-review).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - WebSearch
  - Agent
  - Write
---

# jjstack review-lean - bounded, verified, converging

A review is a doorbell, not a delivery: it tells the author what blocks the
merge, where, and why - then stops. This skill wraps gstack's `/review` with
three things gstack does not do (run the repo's real tooling first, map the
callers outside the diff, post a short verdict to the PR) and one thing every
recall-max reviewer forgets: a budget.

## The equivalence gate

Before any finding is published and before any fix is committed, put the
current text and the proposed text side by side and answer one question:
**name who acts differently, and what they do.** A different output is not
enough. If you cannot name them, the two are equivalent, and:

- a **finding** whose fix is equivalent to the current text is not a finding.
- a **fix** that is equivalent to the text it replaces is not a fix. Do not commit it.
- a **finding** equivalent to one already raised this engagement is not new:
  it means the earlier fix was incomplete. Say that; do not count it again.

This applies identically to prose, code, comments, tests and commit messages.

## Budgets - these are rules, not targets

| Budget | Value | When it is hit |
|---|---|---|
| Wall-clock | **60 min** for the whole review | Stop the current phase, report what ran, mark the rest as a gap |
| Phase 0 | 10 min | Re-run with `--skip-tests`, record "test baseline: not run" |
| jjstack agents | **4**, one message, in parallel | Never add a fifth |
| Findings per agent | 8, highest severity first | The agent drops the rest and says "N more not shown" |
| Findings in the report | **10** | The rest go in one line: "N low-confidence findings dropped" |
| Findings visible in the PR comment | 3 | The lint refuses more; the rest stay in the report beneath |
| Failing-test proofs | 3, P0/P1 only | Everything else is a claim with a quoted line |

Recall-max (every gstack specialist, no small-diff skip) is opt-in with
`--deep`. Without it, gstack's own gating applies.

## Idempotence - the property that outranks recall

**A review of code that has not changed returns the verdict the last review
gave it.** A reviewer whose output changes while its input does not is not
measuring the code, and its approval is worth nothing either.

### First, the distinction every rule below depends on

| | |
|---|---|
| **Pre-existing** | A defect that was there before this diff and would still be there without it. **Out of scope, at any severity**, however plainly you can see it. |
| **A consequence of this diff** | A defect the change *creates*, wherever it lands - including on lines the diff never touched. **In scope at full severity.** |

A caller the new signature breaks, a schema without its migration, an enum
member without its consumers: each is a consequence. The blast-radius walk
and the absence pass are the two lenses that see outside the diff; they
exist to produce exactly this category, and no rule below suppresses them.

Every rule below is scoped to **pre-existing** findings.

1. **Once every finding is resolved, the next review says so and stops.** A
   clean result from a review that ran every applicable lens is a strong
   statement; padding it with a nit is manufacturing work.
2. **No pre-existing finding is raised on a line the diff did not touch**, at
   any severity - including a line an earlier round already read and passed.
3. **A new pre-existing finding on unchanged code is a finding about the
   PREVIOUS review.** Report it as a miss: name what was missed and why the
   earlier pass did not see it. If you cannot say why, it is a new opinion,
   not a defect. No attribution is owed for a consequence of this diff: it
   did not exist when the earlier round ran.

## Setup

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

Store `OUTPUT_DIR` (default `{repo}/jjstack`) and the DNA paths, and
`mkdir -p` it. The 60-minute clock starts now.

**No tree, make one first.** Outside a git repository, where the independent
reviewer runs, `gh pr view` fails with `could not determine base repo`. Fetch
`pull/<PR>/head` into a detached worktree in the session scratchpad, with
`OUTPUT_DIR` beside the tree rather than in it, and work from inside the
tree; first remove any tree an earlier round of the same PR left at that
path. Commands and removal: `references/independent-review.md`.

Resolve the PR once, into a file - the **base** repo, not a fork (from a
detached worktree, add the PR number after `gh pr view`). The `rm` discards
the previous round's head check answer, so a re-run cannot post on it:

```bash
rm -f {OUTPUT_DIR}/head-now && gh pr view --json number,url,commits --jq '"PR_NUM=\(.number)\nPR_REPO=\(.url | sub("^https://github.com/"; "") | sub("/pull/[0-9]+$"; ""))\nPR_SHA=\(.commits[-1].oid)"' > {OUTPUT_DIR}/pr.env 2> {OUTPUT_DIR}/pr.err
```

```bash
gh api user --jq 'if (.login|type)=="string" then "PR_ME=\(.login)" else empty end' >> {OUTPUT_DIR}/pr.env 2>> {OUTPUT_DIR}/pr.err
```

```bash
cat {OUTPUT_DIR}/pr.env {OUTPUT_DIR}/pr.err
```

- exit 0 → continue. `no pull requests found` → **NO_PR**: there is nowhere
  to post; note it for Phase 5. Anything else → **GH_ERROR**: report stderr
  verbatim and stop. Never read an auth or network failure as "no PR".
- **A missing `PR_ME` stops the review; it does not default.** No `PR_ME`
  line is **GH_ERROR**: the detector below filters on it, and an empty
  binding reads every re-review as a first. The `if` is what makes a failed
  call write nothing instead of `PR_ME=null`.

**Bind the tree to the sha**, since every finding is measured against the
tree you stand in (skip on **NO_PR**):

```bash
. {OUTPUT_DIR}/pr.env && [ -n "$PR_SHA" ] && git rev-parse HEAD 2>/dev/null | grep -qxF "$PR_SHA" && echo TREE_AT_HEAD || echo TREE_STALE
```

`TREE_STALE` → the tree is not the head under review (left over, unpushed,
or absent). Do not review it: push, or remake it from the pull ref, and
resolve again.

**First review or re-review.** Every round this skill posts opens with its
attribution line and carries its full report, so the thread is the record.
Read the newest one, substituting the three bracketed values from `pr.env`:

```bash
gh pr view <PR_NUM> --repo <PR_REPO> --json reviews,comments | jq -r --arg me '<PR_ME>' '[(.reviews[]? | {body, at: .submittedAt, who: .author.login}), (.comments[]? | {body, at: .createdAt, who: .author.login})] | map(select(.who == $me and ((.body // "") | startswith("Claude jjstack/skills/review-lean/SKILL.md")))) | sort_by(.at) | last | .body'
```

Both channels, because rounds from before verdicts were posted as reviews
are issue comments; newest by timestamp, because jq's `,` orders by channel;
only this account's rounds, because anyone can type the attribution prefix.
`null` → first review; under NO_PR the newest `{OUTPUT_DIR}/review-*.md` for
this branch stands in. A re-review still runs Phases 0-3 in full (a second
commit can bring a fresh P0): the previous round changes Phase 4's
*filter*, not which phases run.

### Say that a review has started

GitHub has no "under review" state, and a review left unsubmitted is PENDING
and visible only to the person who started it. A commit status shows in the
checks box for everyone, can be a required check, and is not refused on a
self-authored PR. Post one before Phase 0:

```bash
. {OUTPUT_DIR}/pr.env && [ -n "$PR_SHA" ] && gh api -X POST repos/"$PR_REPO"/statuses/"$PR_SHA" -f state=pending -f context=jjstack/review-lean -f description='Review in progress'
```

**A pending status is a promise to replace it.** Phase 5 posts the terminal
one; a run that ends any other way (budget, GH_ERROR, abort) posts
`state=error` with the reason before stopping. A status is
keyed by commit and context, and the newest wins, so a stranded check is
cleared with the same POST above with `state=success`. Skip on NO_PR.
(`description` truncates past 140 characters. The Check Runs API refuses a
personal token: *You must authenticate via a GitHub App*.)

## Phase 0: Pre-flight evidence pack (deterministic, ≤ 10 min)

```bash
cat ~/.claude/skills/jjstack/references/review-preflight.md
```

```bash
~/.claude/skills/jjstack/bin/jjstack-review-preflight --out {OUTPUT_DIR}/preflight
```

```bash
cat {OUTPUT_DIR}/preflight/EVIDENCE-PACK.md {OUTPUT_DIR}/preflight/intent.md {OUTPUT_DIR}/preflight/exclusions.md {OUTPUT_DIR}/preflight/blast-radius.md {OUTPUT_DIR}/preflight/tooling-results.md {OUTPUT_DIR}/preflight/test-baseline.md
```

Read the pack by the reference's rules (options, which rows are gaps, what
is untrusted). **Restate the intent in one sentence** from `intent.md`, not
the diff; if no claim was recoverable, say so. Gaps go to the report's
Degraded section; `FAILED` tooling sections go into the findings, unscored.

## Phase 1: gstack `/review`

```bash
cat ~/.claude/skills/gstack/review/SKILL.md
```

Follow gstack's instructions with these overrides:

- **Output path:** `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`.
- **No auto-fix.** Treat every gstack Step 5b item as ASK: report it, do not
  edit the tree. A review that edits code has to review its own edits, and
  that loop does not converge.
- **Hand the evidence pack to every specialist** - the intent restatement,
  `exclusions.md` (COVERED categories are not reported; IN SCOPE ones got no
  free pass), `blast-radius.md`, and the `FAILED` sections.
- **Gating:** gstack's own, unless the user passed `--deep`.
- Keep gstack's pre-emit gate (quote the motivating line).

## Phase 2: jjstack passes - 4 agents, one message

Launch all four as `Agent` calls in a single message. Each gets the evidence
pack inline (subagents start empty), the diff, and this instruction: *return
at most 8 findings, highest severity first, each as* `file:line | severity
P0-P3 | confidence 0-100 | claim | quoted line | failure scenario (input →
wrong result) | simplest fix (deletion first) | net lines`.

| Agent | Lens |
|---|---|
| **design + context** | is this the right shape: does the change belong in this layer, is the abstraction earned by more than one caller, is it more complex than the problem needs, is there generality no caller needs today; git history of the touched hunks (`git log -p`, `git blame`): reintroduced bugs, contradicted recent intent; names that mislead about what the thing does, and comments that say *what* instead of *why*; comments/docstrings whose "must/never" the diff now violates; CLAUDE.md rules the diff breaks (only rules the file actually states); intent fidelity - a stated case not implemented, or a behaviour change the claim never mentions |
| **correctness** | logic, boundaries, error paths, partial-failure states, races/TOCTOU, leaked handles, missing timeouts; **blast-radius walk** - for every call site in `blast-radius.md`, does it still hold against the new definition? A broken out-of-diff caller is P0 |
| **security** | OWASP-class on the diff: injection, authz/authn gaps, secret exposure, unsafe deserialization, SSRF, LLM trust boundary; use `references/owasp-security/` if present |
| **coverage + absence** | for each new/changed behaviour, is there a test that fails when it regresses? name the untested branch; then *what should have changed and didn't* - schema without migration, enum member without its consumers, signature without its callers or docs, config key without a default |

Skip a lens only when structurally inapplicable (no git history, no tests
possible) and record the skip for the report's Degraded section. Merge the
four result sets with Phase 1's findings; dedup on `file:line` + claim.

## Phase 3: Verify - one batch

For each merged finding (batch them; do not spawn per finding):

0. **Name who is harmed on this tree, today, and what they do wrong.** If the
   answer is "nobody", or "they read it and move on", or "someone first has to
   change something", it is not a finding. A clean review is the expected
   result, not the weak one.
1. **Quote the line.** Open the file, confirm the quoted line is there and
   means what the finding says. Unquotable → confidence 0.
2. **Failure scenario.** The specific input or state that reaches the bug and
   the wrong output it produces. No scenario → it is a nit, not a bug.
3. **Confidence 0-100:** 0 false positive or pre-existing on untouched lines ·
   25 might be real, could not verify · 50 verified, rare or minor · 75
   verified, likely in practice · 100 certain.
4. **Gate:** ≥ 60 → report. 40-59 → one line each under *Unconfirmed*. < 40 →
   dropped, counted.
5. **Library misuse claims:** before asserting a third-party API is used
   wrongly, check the docs for the version the repo pins.

**A guard's title is a claim, and carries the same burden as a finding.** A
check named for a concept while its body tests something else reads as
coverage. Any assertion that scopes its own input (a `sed` range, a file
list, a glob) gets an anti-vacuity floor asserting that input is non-empty,
because an empty input makes a negative assertion pass unconditionally.

Never report: anything a COVERED category in `exclusions.md` already checked;
style not called out in a CLAUDE.md; pre-existing issues (Idempotence); a
test-quality opinion about the suite itself unless the guarded behaviour has
a consequence outside the suite.

**Failing-test proof** for P0/P1 only, at most 3: write the test, run it, tag
the finding PROVEN / DISPROVEN / UNPROVABLE. A DISPROVEN finding stays in the
report with its test quoted. Remove the test before Phase 5.

## Phase 4: Verdict, report, and the re-review rules

Rank by severity, then confidence. Cap the main table at 10.

| Active findings | Default posture |
|---|---|
| Nothing above P3 | `APPROVE` |
| P2s only | `APPROVE` when each P2 is explained, else `CAUTION` - **never `REJECT`** |
| Any P1 | `CAUTION`; `REJECT` only if a P1 is unexplained and unbounded |
| Any P0 | `REJECT` unless it has a landed mitigation |
| A lens or the verification did not run | Drop one step and say so |

The table scopes by **severity**, never by location: a caller the diff breaks
does not live where the diff edited. Only evidence read at the source moves a
finding; author reputation, green CI, diff size and the posture do not.

**Re-review rules** (setup found a previous round):

- Open with `Δ since last review: +N / −M lines` (`git diff --shortstat`
  against the commit the last report names) and the previous finding count.
- Verify only the prior P0/P1: does the reproduction still reproduce? Mark
  each *fixed / still open / regressed*.
- **Raise nothing pre-existing on unchanged code**, per Idempotence rules 2
  and 3. Consequences of this diff stay in scope at full severity.
- **Raise nothing below P1, wherever it lands.** A new low-severity
  observation goes in one line under Coverage notes, uncounted.
- The author may answer "won't fix" on any P2/P3 and it is not re-argued.
- **Every fix passes the equivalence gate before it is committed.** A fix
  that restates the same rule in a new place goes back as "the earlier fix
  was incomplete", with the class named.
- Do not mutation-test or re-review the tests a fix added.
- **If the finding count did not fall, the verdict is `STOP`**: the review is
  generating work faster than it retires it. Say so and hand back to the human.

Write `{OUTPUT_DIR}/review-YYYY-MM-DD.md`, a working file that stays untracked:

```text
## /review: <target>            (commit <sha>, <minutes> min)

**Verdict:** APPROVE | CAUTION | REJECT | STOP - one line why
**Coverage:** <lenses run>/<applicable> · <n> findings, <n> unconfirmed, <n> dropped
**Not read:** <files in the diff no lens opened, or "none">

### Bottom line
2-3 sentences: land it or not, the main risk. Then at most one sentence
naming something the change does well, when it is specific enough to repeat
on purpose.

### Findings   (at most 10 rows)
| Sev | Conf | Location | Finding | Simplest fix | Net lines |
Each row expands below: quoted line, failure scenario, proof tag if any.

### Unconfirmed   (40-59; one line each)
### Degraded   (only if a lens did not run: which, why, what is unknown)
### Guardrails   (2-5 conditions under which this verdict holds)
```

Omit empty sections, except `Not read`, which is stated even when empty:
every file in the diff is read by at least one lens or named on that line.
The report is posted inside the PR comment, so it keeps the comment's rules
from `pr-comment-voice.md`: short dash, repo-relative paths only (never a
pre-flight `repo: /home/...` line), a credential cited by `file:line` and
kind. The lint reads the whole comment, report included.

## Phase 5: Finish

1. The report and `{OUTPUT_DIR}/preflight/` stay untracked: the report rides
   inside the PR comment, and no reviewer pushes to the author's branch.
2. Under **NO_PR** there is nowhere to post: say so and stop. Otherwise load
   the voice:

```bash
cat ~/.claude/skills/jjstack/references/pr-comment-voice.md
```

Compose `{OUTPUT_DIR}/pr-comment-head.md`, the visible part, in the structure
the voice gives, opening with this skill's own attribution line,
`Claude jjstack/skills/review-lean/SKILL.md`. Then join it to the report,
which rides beneath in one collapsed "Full report" block:

```bash
~/.claude/skills/jjstack/bin/jjstack-pr-comment-assemble --head {OUTPUT_DIR}/pr-comment-head.md --report {OUTPUT_DIR}/review-YYYY-MM-DD.md --out {OUTPUT_DIR}/pr-comment.md
```

When every finding is resolved the visible part is exactly this line, with
the report (each prior finding marked fixed) still beneath it:

```text
Claude jjstack/skills/review-lean/SKILL.md: all issues resolved - lgtm - approved
```

When nothing was ever found, the whole comment is this line and nothing else,
written straight to `{OUTPUT_DIR}/pr-comment.md` without the assembler:

```text
Claude jjstack/skills/review-lean/SKILL.md: no findings - lgtm - approved
```

**The verdict goes on the PR as a review**, attached to the commit it judged:

| Verdict | Event |
|---|---|
| `APPROVE` | `--approve` |
| `CAUTION` | `--comment` |
| `REJECT`, `STOP` | `--request-changes` |

**GitHub refuses a state on your own PR** with HTTP 422,
`Can not approve your own pull request`; only `--comment` is accepted.
Resolve authorship:

```bash
gh pr view <PR_NUM> --repo <PR_REPO> --json author --jq .author.login
```

Equal to `PR_ME` → self-authored: post `--comment` whatever the verdict, and
say in the close-out that the review state could not be set, and that a
self-authored round does not satisfy done-done rung 4, which needs a session
that did not write the code (`references/definition-of-done.md`). This is
not a refusal to run: a self-check before handing over is allowed, and the
author filter keeps it out of the reviewer's detector. It is just not the
review the merge waits on.

**Before posting, check the head has not moved.** Every finding was measured
at `PR_SHA`; ask GitHub what the head is now (no clone needed, and the base
repo answers the same way for a fork):

```bash
. {OUTPUT_DIR}/pr.env && [ -n "$PR_REPO" ] && [ -n "$PR_NUM" ] && [ -n "$PR_SHA" ] && gh api "repos/$PR_REPO/pulls/$PR_NUM" --jq .head.sha > {OUTPUT_DIR}/head-now 2> {OUTPUT_DIR}/head-now.err && grep -qxE '[0-9a-f]{40}' {OUTPUT_DIR}/head-now && { grep -qxF "$PR_SHA" {OUTPUT_DIR}/head-now && echo HEAD_UNCHANGED || echo HEAD_MOVED; } || echo HEAD_UNKNOWN
```

- `HEAD_UNCHANGED` → post.
- `HEAD_MOVED` → the author pushed while the round ran. Do not post and do not
  hand-patch the report: re-run against the new head, and say the round is void.
- `HEAD_UNKNOWN` → a value missing from `pr.env`, a `gh` failure, or an answer
  that is not a sha. None is evidence of a push: report **GH_ERROR** with
  `{OUTPUT_DIR}/head-now.err` verbatim, and stop.

<HARD-GATE>
Do NOT run `gh pr review` unless, in the SAME shell command as the post, the PR
identity was sourced, the head check's answer in {OUTPUT_DIR}/head-now is
`PR_SHA`, and `jjstack-pr-comment-lint` exited 0 on {OUTPUT_DIR}/pr-comment.md
under this skill's `--attribution`. This applies to EVERY invocation.
</HARD-GATE>

```bash
. {OUTPUT_DIR}/pr.env && [ -n "$PR_NUM" ] && [ -n "$PR_REPO" ] && [ -n "$PR_SHA" ] && grep -qxF "$PR_SHA" {OUTPUT_DIR}/head-now && ~/.claude/skills/jjstack/bin/jjstack-pr-comment-lint {OUTPUT_DIR}/pr-comment.md --attribution 'Claude jjstack/skills/review-lean/SKILL.md' && gh pr review "$PR_NUM" --repo "$PR_REPO" <EVENT> --body-file {OUTPUT_DIR}/pr-comment.md
```

**This chain is the one sanctioned exception to one-command-per-Bash-call.**
Shell state does not persist between calls, so `$PR_NUM` set earlier expands
empty, and a lint run as its own call gates nothing. Never split it. Lint
exit 4 is a credential in the comment: cite `file:line` and its kind, and
re-run. Exit 1 is budget or shape: move findings from the visible part into
the report, never delete them.

**Then replace the pending status.** It answers only whether anything blocks
the merge, so it is binary where the verdict is not:

| Verdict | Commit status |
|---|---|
| `APPROVE` | `success` |
| `CAUTION`, `REJECT` | `failure` |
| `STOP` | `error` |

`CAUTION` fails the check because it carries a P1, and a P1 blocks.

```bash
. {OUTPUT_DIR}/pr.env && [ -n "$PR_SHA" ] && gh api -X POST repos/"$PR_REPO"/statuses/"$PR_SHA" -f state=<STATE> -f context=jjstack/review-lean -f description='<VERDICT>: <N> blocking, <K> non-blocking'
```

**Confirm it landed**; GitHub accepts some review calls and does nothing:

```bash
gh pr view <PR_NUM> --repo <PR_REPO> --json reviewDecision,reviews,statusCheckRollup --jq '{decision:.reviewDecision, last:(.reviews|last|{state,author:.author.login}), status:[.statusCheckRollup[]?|select(.context=="jjstack/review-lean")|.state]}'
```

An empty `decision` after `--approve` means only the body landed: report
that, and do not restate the verdict as though it stuck.

3. **`gh pr edit` does not work on this account**, whatever the flag: it dies
   on a Projects-classic GraphQL error and writes nothing. Edit a title or
   body with `PATCH /repos/<PR_REPO>/pulls/<PR_NUM>`. Requesting a reviewer is
   the author's move; this call returns 200 even for a login it ignores, so
   read `requested_reviewers` back:

```bash
echo '{"reviewers":["<login>"]}' | gh api -X POST repos/<PR_REPO>/pulls/<PR_NUM>/requested_reviewers --input -
```

4. Update `README.md` only if the change under review affects it.
5. Close with the verdict, the minutes elapsed, whether the review state was
   set or refused, and the URL the post printed.
