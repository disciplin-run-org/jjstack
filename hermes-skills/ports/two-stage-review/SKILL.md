---
name: two-stage-review
description: >
  Two-stage code review: first pass verifies the change matches the spec
  (did you build what was asked?); second pass verifies code quality (is it
  good code?). Separating these catches a different class of bug than a
  single-pass review. Use when reviewing a subagent's work, a worker's
  output, or a PR where both correctness-to-spec and code quality matter.
  Trigger on: "two-stage review", "stage review", "spec-then-quality",
  "review against spec and quality", or after a subagent completes an
  implementation task.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Agent
---

# two-stage-review — Spec compliance, then code quality

Most code reviews conflate two questions:

1. **Did you build what was asked?** (spec compliance)
2. **Is it good code?** (quality)

These have different failure modes and different reviewers. Running them
together causes the obvious problem — a reviewer who approves "good code"
that silently doesn't match the spec, or rejects working code because of
style nits that don't matter to the deliverable.

This skill runs them as two separate passes in a fixed order.

## When to use

**Good fits:**
- After a subagent completes a task against a spec or work-order
- Reviewing a PR that implements a `/work-order` deliverable
- Before landing any non-trivial change where both correctness and quality matter

**Skip for:**
- Trivial fixes (typo, version bump) — single-pass is fine
- Exploratory / prototype code where "spec" doesn't exist yet
- Post-merge audits (use `/requesting-code-review` instead)

## The process

```
┌─────────────────────┐
│ Stage 1: Spec pass  │
│  Does code match    │
│  the spec?          │
└──────────┬──────────┘
           │ pass
           ▼
┌─────────────────────┐
│ Stage 2: Quality    │
│  Is it good code?   │
└──────────┬──────────┘
           │ pass
           ▼
       Approved
```

If Stage 1 fails → fix spec gaps → re-run Stage 1 (do not advance).
If Stage 2 fails → fix quality issues → re-run Stage 2 only.

### Stage 1: Spec compliance

**Reviewer persona:** Product engineer. Only reads the spec/work-order and
the diff. Does NOT evaluate code quality.

**Questions:**
- Does every deliverable in the spec/work-order exist in the diff?
- Does the diff introduce anything the spec did not ask for? (scope creep)
- Does every "Verify" step in the spec pass? (run them)
- Are any "Out of scope" items violated?

**Output shape:**
```
## Stage 1 result: PASS | FAIL

### Deliverables checklist
- [x] <deliverable 1> — file/line reference
- [ ] <deliverable 2> — MISSING

### Scope creep
- None | <list of out-of-scope changes>

### Verify steps
- [x] `pytest tests/` — green
- [x] `curl /health` — 200

### Decision
PASS / FAIL + one-line reason
```

**Fail → stop here.** Send back to implementer. Do NOT run Stage 2 on code
that does not match the spec — quality review of the wrong thing is waste.

### Stage 2: Code quality

**Reviewer persona:** Senior engineer. Reads the diff plus surrounding code.
Does NOT re-check spec compliance.

**Questions:**
- Correctness: off-by-one, null handling, race conditions, resource leaks
- Consistency: matches existing patterns in the codebase
- Error handling: no silent catches, no unchecked nulls
- Tests: coverage proportional to risk (Kano level if known)
- Simplicity: premature abstractions, unused parameters, dead branches
- Security: injection vectors, secrets, authz gaps
- Performance: obvious O(n²) where O(n) works, unbounded memory
- Project rules followed (CLAUDE.md, AGENTS.md)

**Output shape:**
```
## Stage 2 result: PASS | APPROVE-WITH-NITS | FAIL

### Findings (by severity)
- **Critical:** <must fix before land>
- **High:** <should fix before land>
- **Medium:** <fix soon>
- **Low / nit:** <optional>

### Decision
PASS (land as-is) / APPROVE-WITH-NITS (land, file follow-up) / FAIL (block)
```

## Running the stages

### Inline (same session)
Run Stage 1 first, then Stage 2 after Stage 1 passes.

### Via subagents (recommended for non-trivial reviews)
Use `delegate_task` with separate subagents per stage. Fresh context per
stage prevents context pollution from the implementer's session.

Stage 1 subagent prompt example:
```
Context: I have a completed implementation of <spec>. Verify the implementation
matches the spec. Do NOT evaluate code quality — that's Stage 2.
Only check: (1) every deliverable exists, (2) no scope creep, (3) every verify step passes.

Spec: <paste or file path>
Diff: <git diff output or commit range>

Report using the Stage 1 output shape from /two-stage-review.
```

## Interaction with other skills

- **`/work-order`** — produces the spec Stage 1 reviews against. A work order
  without Deliverables + Verify sections is unreviewable at Stage 1.
- **`/requesting-code-review`** — single-pass adversarial. Use `/two-stage-review`
  when you specifically need the spec-then-quality separation.
- **`/lean`** — two-stage review requires ~6–10 tool calls per stage minimum.
  Budget accordingly.
- **`/receiving-code-review`** — how to process the findings this skill produces.

## Anti-patterns

- **Skipping Stage 1 because "the spec is obvious"** — this is where 80% of
  silent misalignment bugs live. Always run it.
- **Running both stages in one pass** — defeats the separation.
- **Failing Stage 2 for nits** — nits are APPROVE-WITH-NITS, not a block.
- **Re-running Stage 1 after Stage 2 fixes** — Stage 2 doesn't change deliverables.
- **Using the same context for both stages** — fresh subagent per stage is the point.

## Attribution

Two-stage-review pattern adapted from `obra/superpowers` (MIT) — the
spec-reviewer / code-quality-reviewer split in their subagent-driven-development.
