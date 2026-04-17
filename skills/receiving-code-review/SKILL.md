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
- Self-review (use `/review` directly — you're the reviewer, not the receiver)
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
"Out of scope" handling.
