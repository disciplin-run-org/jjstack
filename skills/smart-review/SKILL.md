---
name: smart-review
description: >
  Automatically invokes the Anthropic code-review plugin before creating or merging
  pull requests. Runs specialized parallel agents for CLAUDE.md compliance, bug detection,
  history context, comment analysis, and code quality. Triggers before: creating PRs,
  merging PRs, or when asked to review changes. Do NOT trigger for: draft PRs,
  WIP branches, or when the user explicitly skips review.
disable-model-invocation: false
---

# Smart Review — Automatic PR Code Review

## Purpose

Automatically invoke Anthropic's `/code-review` plugin before PR creation or merge
to catch issues before a human reviewer sees them. This skill decides WHEN to review —
the plugin handles HOW (5 parallel specialized agents with confidence scoring).

## Decision Framework

### INVOKE /code-review when:

1. **Before creating a PR** — After `/ship` or `gh pr create`, but before the PR
   is actually submitted. Run the review on the diff against the base branch.

2. **Before merging a PR** — When asked to merge or land a PR. Review first,
   merge only if no high-confidence issues found.

3. **Explicit review request** — User asks "review this", "check my changes",
   or "is this ready for PR?"

4. **After jjstack's /review wrapper** — The jjstack `/review` wrapper handles
   gstack's review process. Smart-review adds Anthropic's multi-agent review
   on top for additional coverage.

### DO NOT invoke /code-review when:

1. **Draft PRs** — Drafts are work-in-progress, not ready for formal review.

2. **WIP branches** — Branch names starting with `wip/` or commits with "WIP" prefix.

3. **User explicitly skips** — "skip review", "merge without review", "YOLO".

4. **Already reviewed this session** — Don't re-review the same diff.

5. **No PR context** — If there's no PR number or diff to review, nothing to do.

## Invocation Protocol

When review IS warranted:

1. **Announce briefly:** "Running Anthropic code review with 5 specialized agents."
2. **Invoke:** `/code-review`
3. **The plugin launches:**
   - Agent #1: CLAUDE.md compliance check
   - Agent #2: Bug and logic error scan
   - Agent #3: Git blame/history context analysis
   - Agent #4: Previous PR comment patterns
   - Agent #5: Code comment and documentation audit
4. **Results filtered:** Only issues with confidence >= 80 are reported.
5. **Present findings** to user before proceeding with PR/merge.

## Integration with jjstack workflow

The recommended jjstack workflow before shipping:

```
/review          → gstack adversarial review (enhanced by jjstack to 10/10)
/code-review     → Anthropic multi-agent review (auto-triggered by smart-review)
/ship            → create PR and push
```

Smart-review bridges the gap between jjstack's `/review` wrapper (which focuses on
the design document and quality score) and Anthropic's `/code-review` (which focuses
on the actual code diff).

## Graceful Failure

If `/code-review` is not available (plugin not installed):
1. **Do not error out.** Skip the automated review.
2. **Inform once per session:** "The code-review plugin is not installed.
   Run `./setup` in your jjstack directory to install Anthropic plugins."
3. **Continue normally.** The jjstack `/review` wrapper still provides review coverage.
