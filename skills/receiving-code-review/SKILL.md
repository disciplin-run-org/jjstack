---
name: receiving-code-review
description: >
  Companion to /review, /two-stage-review, and /smart-review — the skill
  for being the one ON THE RECEIVING END of a code review. Process
  feedback systematically: triage by severity, agree/disagree with
  explicit reasoning, fix what needs fixing, push back on what doesn't,
  and close the loop. Prevents the two failure modes: silent capitulation
  (accepting bad feedback to end the conversation) and silent
  stonewalling (dismissing feedback without engagement). Use when a code
  reviewer has left comments on your PR, a /two-stage-review returned
  findings, or a worker reports that a reviewer rejected its work.
  Trigger on: "responding to review", "process review feedback", "review
  comments on PR", "reviewer said X", "address these findings", or when
  received output from /review, /two-stage-review, or /smart-review.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# receiving-code-review — Responding to review feedback

Code review is a dialog, not a directive. The reviewer surfaces concerns;
the author decides which to act on, which to push back on, and how. This
skill makes that dialog systematic so neither side ends up in the two
failure modes:

- **Silent capitulation** — accepting every comment to end the
  conversation. Produces code that is worse than either reviewer or
  author intended, because every change has a reason and compromises
  lose them.
- **Silent stonewalling** — marking every comment "resolved" without
  engaging. Burns the reviewer's trust and guarantees a rubber-stamp
  next round.

Adapted from `obra/superpowers`' `receiving-code-review`.

## When to use

**Good fits:**
- Processing findings from `/two-stage-review`, `/review`, or `/smart-review`
- Responding to PR comments (from humans or the Anthropic code-review plugin)
- A worker reported back with reviewer feedback that needs triage
- You were asked "can you address these findings?"

**Skip for:**
- Reviewing someone else's PR (use `/review` directly — you're the reviewer,
  not the receiver). A round you run on your own PR does not satisfy
  done-done rung 4, which needs a session that did not write the code; see
  `references/independent-review.md`.
- Trivial nits on throwaway code (fix or ignore, no ceremony)
- Feedback that is entirely out of scope (that's a new task, open an issue)

## The process

```
┌──────────────────────────┐
│ Review received          │
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ Triage: bucket each item │
│ by severity + type       │
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ For each item: agree or  │
│ disagree, with reason    │
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ Act: fix the agrees,     │
│ reply to the disagrees   │
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ Verify fixes work        │
│ (/verify-before-done)    │
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ Close the loop —         │
│ summarize resolved/open  │
└────────────┬─────────────┘
             ▼
┌──────────────────────────┐
│ Re-read the thread in    │
│ the same call as the     │
│ merge                    │
└──────────────────────────┘
```

## Step 1: Triage

Bucket every finding into one of these. Do not skip this step — it
changes what "resolve" means per item.

| Severity | Definition | Default action |
|---|---|---|
| **Critical** | Bug, security issue, data loss risk, broken build | Fix before merge, no exception |
| **High** | Wrong approach, significant design flaw, violated project rule | Fix or make the case for why not |
| **Medium** | Could be better but ships as-is | Fix if cheap, defer if not |
| **Low / nit** | Style, naming, personal preference | Fix at author's discretion |
| **Question** | Reviewer didn't understand something | Answer; may reveal needed clarification in code or comment |
| **Out of scope** | Valid concern but not this change | Thank reviewer, open issue, move on |

If the reviewer didn't label severity, label it yourself before responding.
Ambiguous severity is the fastest way to miscommunicate.

## Step 2: Agree or disagree (with reason)

For each finding, take a position:

### Agree

The finding is correct. State what you'll change and move to Step 3.

Template:
```
Agreed — <what was wrong> <will change / has been fixed in <commit>>.
```

### Disagree

The finding is wrong, incomplete, or the trade-off favors the current
code. You must give a reason. "Disagree, keeping as-is" without a reason
is stonewalling.

Template:
```
Disagree — <reason>. <What the reviewer may be missing, OR what
trade-off led to this choice>. Open to changing if <counter-argument>.
```

Disagreement is legitimate. Reviewers aren't always right. But the
reason must be in writing so future-you (or future reviewers) can
follow the logic.

### Need to investigate

The finding might be right — you don't know yet. Do not silently ignore.

Template:
```
Investigating — <what I'm checking>. Will report back by <when>.
```

Then actually investigate and report back.

## Step 3: Act

For agreed items: make the fix. Group related fixes into commits. Don't
fix-and-squash if the review is ongoing — reviewers need to see what
changed per round.

**A fix to a document is not done when the named sentence is changed. It
is done when the whole document agrees with the change.** A finding names
one place; the idea behind it usually lives in several. Before committing:

1. Find every place the *idea* is stated — grep the concept, not the
   wording the finding used. `git log -S '<phrase>' --stat` on the phrase
   you are removing shows what else that commit touched — before the branch
   is squashed; after, it names the whole feature.
2. Read each one against the new text. If two places now say different
   things, the fix is incomplete, and committing it hands the reviewer the
   next round for free.
3. If the same idea is restated in three or more places, that is the
   defect: state it once and have the others refer to it. A bullet cannot
   drift from a definition it does not restate. A place read on its own — a
   frontmatter `description`, a HARD-GATE block — restates by design; check
   that it agrees, do not collapse it.

This applies to prose exactly as it applies to code — a skill, a policy or
a README is machine instructions, and a contradiction in it is a bug. The
measurement behind this step is in `/review`'s equivalence gate: three
rounds on one scoping rule, each fix restating the scope in a place the last
one had not touched.

For disagreed items: write the disagreement response in the review
thread. Be specific. "Already handled elsewhere" is not an answer;
"Already handled in `auth_middleware.py:L42`" is.

For questions: answer directly. If the reviewer's confusion suggests the
code itself is unclear, also add a comment in code — the next reader
will have the same question.

For out-of-scope: open a follow-up issue. Link it in the response.

## Step 4: Verify fixes

Every fix is a new change. Every new change goes through
`/verify-before-done`. A fix that breaks something else is a worse
outcome than the original finding.

## Step 5: Close the loop

Reply on the review with a summary:

```
## Review response

### Addressed
- <finding 1>: fixed in <commit or description>
- <finding 2>: fixed in <commit>

### Disagreed
- <finding 3>: <one-line reason + thread pointer>

### Follow-up issues opened
- <finding 4>: <link to issue>

### Outstanding
- <finding 5>: investigating, will follow up by <when>
```

Then re-request review. The reviewer should not have to hunt for your
responses.

## Step 6: Re-read the thread in the same breath as the merge

**`MERGEABLE` is not `unreviewed`.** They are different questions and only one
of them is about your change. GitHub answers whether the branches conflict; it
says nothing about whether a review is sitting on the pull request that you
have not read. Reading only the first is how a review gets merged over.

So the last thing before a merge is a check that **exits non-zero** when the
thread has moved, chained to the merge so no turn can pass between them:

```bash
~/.claude/skills/jjstack/bin/jjstack-pr-unread-check --pr <N> --repo <REPO> --since <the moment you last READ the thread> && gh pr merge <N> --repo <REPO> --squash --delete-branch
```

**The exit code is the whole mechanism, and this is the second attempt at it.**
The first printed `gh pr view` and called that the chain. `gh pr view` exits 0
whether or not anything is unread, so `read && merge` gated on nothing while
looking exactly like a gate, and it left the reader to compare timestamps by
eye, which puts a turn between the read and the merge by construction. The
reviewer-side chain in `/review` works for the one reason that one was missing:
its lint exits non-zero. This is the author side's equivalent.

`--since` is when you last actually **read** the thread, not when you last
looked at the merge button. Exit 1 names what arrived and refuses the merge;
exit 3 means the thread could not be read, which is never treated as nothing
new.

All three surfaces are checked, because a person can leave something on any of
them and they are three different shapes: an issue comment carries `createdAt`,
a submitted review carries `submittedAt` and no `createdAt` at all, and a reply
inside an inline review thread is on neither list — `gh pr view` cannot return
it. Comparing fewer than all three is how an unread item hides behind a stale
date on another surface.

A review that is unread at merge time has cost the whole engagement: its
findings are on `main` before anyone answers them, and the author who merged
is the one who has to go back and fix them.

Under a stacked or retargeted pull request this matters more, not less. The
window between "I checked it was clean" and "I merged" is where the review
lands, and the check that fills that window is the only thing that closes it.

**Measured:** the review of jjstack #29 posted `CAUTION` with three blocking
findings at 13:12. The pull request was merged at 13:21, on a `mergeStateStatus`
of `CLEAN` read before the review existed. All three shipped in a release. No
step was skipped in bad faith — the step did not exist.

## When the reviewer is another AI

Two-stage reviews, `/smart-review`, and Anthropic code-review plugin
findings are AI-generated. Same process — same dignity. Differences:

- AI reviewers sometimes hallucinate findings ("this function doesn't
  handle null" when it does). Check the cited code BEFORE agreeing.
  "Looks right" is not verification.
- AI reviewers over-cite security concerns. Apply the severity matrix;
  don't assume every "security" label is Critical.
- AI reviewers will happily accept weak responses. If you disagree, you
  don't need to soften the tone for social reasons.

## When pushback is met with insistence

A reviewer who keeps pushing on a disagreement is telling you one of
three things:

1. They have additional context you don't. Ask what they know that you
   don't — often this uncovers a real concern.
2. They're rigid about a rule that doesn't serve this case. Cite the
   case-specific reason the rule doesn't apply here.
3. The disagreement is actually about values, not facts. Escalate — get
   a tiebreaker (another reviewer, `/codex` for a second opinion).

Do NOT silently capitulate at this stage. "Fine, I'll change it" without
agreement leaves a known-wrong change in the code.

## Interaction with other skills

- **`/two-stage-review`** — produces the findings this skill consumes. If
  Stage 1 failed, fix the spec gap and re-request Stage 1. If Stage 2
  failed, fix the quality issue and re-request Stage 2.
- **`/review`**, **`/smart-review`** — same: they produce findings; this
  skill processes them.
- **`/verify-before-done`** — run after every fix committed in response
  to a review. A fix without verify is a bet, not a resolution.
- **`/codex`** — tiebreaker for values-based disagreements.
- **`/work-order`** — if the review reveals the spec was underspecified,
  update the work order for next time (same spec + different reviewers
  = same finding).

## Anti-patterns

- **Marking everything "resolved" without a response** — silent
  stonewalling; the reviewer loses trust and escalates.
- **Agreeing with every finding to end the review faster** — silent
  capitulation; code gets worse with every round.
- **Fixing a finding but not verifying the fix** — leaves a different
  bug behind.
- **Fixing the sentence the finding named and nothing else** — the idea
  lives elsewhere too; the reviewer finds the sibling next round and you
  have paid for two rounds to move one word.
- **Merging on a mergeability check instead of a fresh read** — `MERGEABLE`
  answers whether the branches conflict, not whether anyone has reviewed you.
  A review that lands in the gap between the two ships unread.
- **Arguing style nits for more than two rounds** — it's a nit, pick
  one, move on.
- **Taking disagreement personally** — review is about the code, not
  you. The reviewer is trying to help.
- **Burying responses in a 20-item comment soup** — use the Step 5
  structured summary so the reviewer can find responses.

## Attribution

Pattern adapted from `obra/superpowers` `receiving-code-review` (MIT).
jjstack additions: AI-reviewer-specific section, tiebreaker via `/codex`,
work-order-feedback loop for underspecified tasks, severity matrix with
"Out of scope" handling, whole-document sweep before committing a fix
(Step 3), re-reading the thread in the same command as the merge (Step 6).
