---
name: receiving-code-review
description: >
  Companion to /requesting-code-review, /two-stage-review — the skill
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
  received output from /requesting-code-review or /two-stage-review.
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
skill makes that dialog systematic to avoid the two failure modes:

- **Silent capitulation** — accepting every comment to end the conversation.
  Produces code that is worse than either reviewer or author intended.
- **Silent stonewalling** — marking every comment "resolved" without engaging.
  Burns the reviewer's trust and guarantees a rubber-stamp next round.

## When to use

**Good fits:**
- Processing findings from `/two-stage-review`, `/requesting-code-review`, or GitHub PR comments
- Responding to PR comments (from humans or AI code-review tools)
- "Can you address these findings?"

**Skip for:**
- Self-review (use `/requesting-code-review` directly)
- Trivial nits on throwaway code (fix or ignore, no ceremony)
- Feedback entirely out of scope (open an issue, move on)

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

Bucket every finding. Do not skip — it changes what "resolve" means per item.

| Severity | Definition | Default action |
|---|---|---|
| **Critical** | Bug, security issue, data loss risk, broken build | Fix before merge, no exception |
| **High** | Wrong approach, significant design flaw, violated project rule | Fix or make the case for why not |
| **Medium** | Could be better but ships as-is | Fix if cheap, defer if not |
| **Low / nit** | Style, naming, personal preference | Fix at author's discretion |
| **Question** | Reviewer didn't understand something | Answer; may reveal needed code clarification |
| **Out of scope** | Valid concern but not this change | Thank reviewer, open issue, move on |

If the reviewer didn't label severity, label it yourself before responding.

## Step 2: Agree or disagree (with reason)

### Agree
```
Agreed — <what was wrong> <will change / has been fixed in <commit>>.
```

### Disagree
```
Disagree — <reason>. <What the reviewer may be missing, OR what
trade-off led to this choice>. Open to changing if <counter-argument>.
```

Disagreement is legitimate. Reviewers aren't always right. But the reason
must be in writing.

### Need to investigate
```
Investigating — <what I'm checking>. Will report back by <when>.
```

Then actually investigate and report back.

## Step 3: Act

For agreed items: make the fix. Group related fixes into commits. Don't
fix-and-squash if the review is ongoing — reviewers need to see what changed.

For disagreed items: write the disagreement in the review thread. Be specific.

For questions: answer directly. If the confusion suggests the code is unclear,
also add a comment in code.

For out-of-scope: open a follow-up issue. Link it in the response.

## Step 4: Verify fixes

Every fix is a new change. Run `/verify-before-done`. A fix that breaks
something else is a worse outcome than the original finding.

## Step 5: Close the loop

```
## Review response

### Addressed
- <finding 1>: fixed in <commit or description>

### Disagreed
- <finding 2>: <one-line reason + thread pointer>

### Follow-up issues opened
- <finding 3>: <link to issue>

### Outstanding
- <finding 4>: investigating, will follow up by <when>
```

Then re-request review.

## When the reviewer is an AI

AI reviewers sometimes hallucinate findings. Check the cited code BEFORE
agreeing — "looks right" is not verification. AI reviewers also over-cite
security concerns. Apply the severity matrix; don't assume every "security"
label is Critical.

## When pushback is met with insistence

1. They have additional context you don't — ask what they know that you don't.
2. They're rigid about a rule that doesn't serve this case — cite the case-specific reason.
3. The disagreement is about values, not facts — get a tiebreaker (another reviewer).

Do NOT silently capitulate at this stage.

## Anti-patterns

- **Marking everything "resolved" without a response** — silent stonewalling
- **Agreeing with every finding to end the review faster** — silent capitulation
- **Fixing a finding but not verifying the fix** — leaves a different bug behind
- **Arguing style nits for more than two rounds** — pick one, move on
- **Burying responses in a 20-item comment soup** — use the Step 5 structured summary

## Attribution

Pattern adapted from `obra/superpowers` `receiving-code-review` (MIT).
Additions: AI-reviewer-specific section, severity matrix with "Out of scope" handling.
