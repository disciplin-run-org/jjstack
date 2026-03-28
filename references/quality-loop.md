# Quality Iteration Loop Protocol

This protocol is loaded by all jjstack wrapper skills that iterate reviews to 10/10.
It replaces blind looping with intelligent escalation — fixing what the AI can fix,
and asking the user about what requires human judgment.

## When to run

Run this loop when the gstack skill's review score is **less than MIN_SCORE**
(default: 10, configured in `jjstack.config.yaml`) and iteration count is below
**MAX_ITERATIONS** (default: 3).

---

## Step 1: Dispatch reviewer subagent

Use the **Agent tool** to dispatch a fresh review subagent. The subagent prompt MUST:

- Present the document/artifact as a **first-time review** — no prior scores, no
  iteration count, no change history, no context about what was "fixed." This prevents
  anchoring and score inflation.

- Include this classification instruction in the subagent prompt:

  > For each issue you find, classify it as either `[AI-FIXABLE]` or `[NEEDS-HUMAN]`.
  >
  > **[AI-FIXABLE]** — the correct fix is deterministic from the document and codebase:
  > factual inconsistencies between sections, missing error handling for known failure
  > modes, incomplete edge case coverage where the behavior is obvious, structural
  > problems, violations of stated requirements, feasibility issues where a better
  > approach is obvious.
  >
  > **[NEEDS-HUMAN]** — two senior engineers could reasonably disagree on the right
  > answer: ambiguous requirements with multiple valid interpretations, design trade-offs
  > with no objectively correct answer, scope decisions, missing domain/business
  > knowledge, contradictions in source material, taste/preference decisions.

- Review against these 5 dimensions:
  1. **Completeness** — Requirements addressed? Edge cases covered?
  2. **Consistency** — Parts agree? No contradictions?
  3. **Clarity** — Can an engineer implement without questions?
  4. **Scope** — Document creep? YAGNI violations?
  5. **Feasibility** — Actually buildable? Hidden complexity?

The subagent returns: quality score (1-10), and for each issue: dimension,
description, classification tag (`[AI-FIXABLE]` or `[NEEDS-HUMAN]`), and
suggested fix or best-guess resolution.

---

## Step 2: Triage issues

Separate the returned issues into two lists:

- **AI_FIXABLE**: issues tagged `[AI-FIXABLE]`
- **HUMAN_ISSUES**: issues tagged `[NEEDS-HUMAN]`

---

## Step 3: If HUMAN_ISSUES exist, pause and ask the user

Before fixing anything, use **AskUserQuestion** to present the human-required issues.

Format:

> **Quality review found {N} issues that need your input** (plus {M} issues I can
> fix myself).
>
> {For each HUMAN_ISSUE, numbered:}
>
> **{i}. [{Dimension}] {Plain-English description}**
> Why I can't decide this: {one sentence explaining the ambiguity/trade-off}
> My best guess if you want me to just pick: {what the AI would choose}

Options:
- **A) "Answer each question now"** — Provide your decisions. I'll fix the AI-fixable
  issues and apply your answers.
- **B) "Use my best guesses for all"** — I'll proceed with assumptions and mark each
  with a `<!-- ASSUMPTION: {description} — user deferred to AI judgment -->` comment
  so downstream reviewers can spot them.
- **C) "Stop here"** — Save the current state with unresolved issues listed in a
  `## Reviewer Concerns` section. Report the honest score.

**If user picks A:** Collect their answers (one AskUserQuestion per decision if
multiple questions). Then proceed to Step 4 with all issues resolved.

**If user picks B:** Treat all HUMAN_ISSUES as AI-FIXABLE using the reviewer's
"best guess." Mark each assumption with the HTML comment. Proceed to Step 4.

**If user picks C:** Skip to Step 6 convergence exit — write Reviewer Concerns
section and report honestly.

---

## Step 4: Fix issues

Fix all AI-fixable issues (and answered/assumed human issues) in the document
using the Edit tool.

---

## Step 5: Re-dispatch for review

Dispatch a **new fresh subagent** (return to Step 1). The new reviewer sees the
fixed document cold — no knowledge of prior iterations.

---

## Step 6: Exit conditions

The loop exits when ANY of these conditions is met:

1. **Score >= MIN_SCORE** — Success. Report: "Final quality score: {X}/10."

2. **Only HUMAN_ISSUES remain, and they have already been asked about** — These are
   design decisions, not quality defects. Report: "Score: {X}/10. Remaining issues
   are design decisions that were addressed with the user."

3. **MAX_ITERATIONS reached** — Save as-is. Add a `## Reviewer Concerns` section
   listing all unresolved issues. Report: "Reached max iterations ({N}). Final
   score: {X}/10. Remaining issues listed in Reviewer Concerns."

**CRITICAL: Never inflate the score to exit the loop.** If issues remain, report
the honest score. The user deserves accurate information.

---

## Convergence guard

If an `[AI-FIXABLE]` issue is returned by the reviewer on **two consecutive
iterations** with essentially the same description (the fix didn't resolve it):

- **Reclassify it as `[NEEDS-HUMAN]`** on the next pass
- This prevents infinite loops on issues that look fixable but aren't

The guard ensures the loop converges: either issues get fixed, get escalated to
the user, or hit MAX_ITERATIONS — it never spins on unfixable problems.
