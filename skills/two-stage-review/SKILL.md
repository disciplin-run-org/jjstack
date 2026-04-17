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

This skill runs them as two separate passes in a fixed order, with explicit
gates between them. Adapted from `obra/superpowers`' subagent-driven-development.

## When to use

**Good fits:**
- After a subagent or Quartermaster worker completes a task against a spec
- Reviewing a PR that implements a `/work-order` deliverable
- Before landing any non-trivial change where both correctness and quality matter
- After `/jj-code` produces an implementation

**Skip for:**
- Trivial fixes (typo, version bump, dependency update) — single-pass is fine
- Exploratory / prototype code where "spec" doesn't exist yet
- Post-merge audits (use `/review` or `/cso` instead)

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
If Stage 2 fails → fix quality issues → re-run Stage 2 only (Stage 1 has passed).

### Stage 1: Spec compliance

**Reviewer persona:** Product engineer. Only reads the spec/work-order and
the diff. Does NOT evaluate code quality.

**Questions:**
- Does every deliverable in the spec/work-order exist in the diff?
- Does the diff introduce anything the spec did not ask for? (scope creep)
- Does every "Verify" step in the spec pass? (run them)
- Are any "Out of scope" items violated?
- If the spec includes acceptance tests, do they pass?

**Output shape:**
```
## Stage 1 result: PASS | FAIL

### Deliverables checklist
- [x] <deliverable 1> — file/line reference
- [x] <deliverable 2> — file/line reference
- [ ] <deliverable 3> — MISSING

### Scope creep
- None | <list of out-of-scope changes>

### Verify steps
- [x] `pytest tests/` — green
- [x] `curl /health` — 200

### Decision
PASS / FAIL + one-line reason
```

**Fail → stop here.** Send back to implementer with the checklist. Do NOT
run Stage 2 on code that does not match the spec — quality review of the
wrong thing is waste.

### Stage 2: Code quality

**Reviewer persona:** Senior engineer on the project. Reads the diff plus
surrounding code. Does NOT re-check spec compliance.

**Questions:**
- Correctness: off-by-one, null handling, race conditions, resource leaks
- Consistency: matches existing patterns in the codebase
- Error handling: no silent catches, no unchecked nulls, no swallowed errors
- Tests: coverage proportional to risk (Kano level if known)
- Simplicity: premature abstractions, unused parameters, dead branches
- Security: injection vectors, secrets, authz gaps (`/security-review` for deep)
- Performance: obvious O(n²) where O(n) works, unbounded memory
- CLAUDE.md compliance: local project rules followed

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

```
Stage 1: /two-stage-review spec <path-to-spec-or-work-order>
Stage 2: /two-stage-review quality
```

### Via subagents (fresh context per stage, recommended for non-trivial reviews)

Use `Agent` tool with `subagent_type: feature-dev:code-reviewer` for each
stage. Pass the stage-specific prompt. Fresh subagents prevent context
pollution from the implementer's session.

Example Stage 1 prompt to subagent:
```
Context: I have a completed implementation of <spec>. I need you to verify
the implementation matches the spec. Do NOT evaluate code quality — that's
a separate review. Only check: (1) every deliverable exists, (2) no scope
creep, (3) every verify step passes.

Spec: <paste or file path>
Diff: <git diff output or commit range>

Report using the Stage 1 output shape from /two-stage-review.
```

### Via Quartermaster workers

Send the stage-specific work order via `qm_send`. One worker per stage.
Do NOT run both stages in the same worker — fresh context per stage is
the point of the separation.

## Interaction with other skills

- **`/work-order`** — produces the spec that Stage 1 reviews against. A
  work order without Deliverables + Verify sections is unreviewable at
  Stage 1; fix the work order first.
- **`/review`** — existing jjstack review is single-pass adversarial. Use
  `/two-stage-review` when you specifically need the spec-then-quality
  separation. Use `/review` for post-merge audits and deep adversarial
  passes.
- **`/smart-review`** — triggers the Anthropic code-review plugin
  automatically. That plugin does general quality review; it does not
  enforce spec compliance. Run `/two-stage-review` first for spec-critical
  work, `/smart-review` as a quality safety net.
- **`/lean`** — lean mode caps tool-call budget. Two-stage review requires
  at least ~6–10 tool calls per stage (read spec, read diff, verify).
  Budget accordingly.
- **`/security-review`** — orthogonal. Stage 2 surfaces obvious security
  issues; `/security-review` is deep CWE analysis. Run `/security-review`
  separately when the change warrants it.

## Anti-patterns

- **Skipping Stage 1 because "the spec is obvious"** — this is where 80%
  of silent misalignment bugs live. Always run it.
- **Running both stages in one pass** — defeats the separation. Different
  questions, different reviewers, different failure modes.
- **Failing Stage 2 for nits** — nits are a valid PASS-WITH-NITS outcome,
  not a block. Critical/High block; Medium is a conversation; Low is
  optional.
- **Re-running Stage 1 after Stage 2 fixes** — Stage 2 changes code quality
  without changing deliverables. No need to re-run Stage 1 unless the
  quality fixes touched deliverable surfaces.
- **Using the same reviewer for both stages in the same session** — context
  from Stage 1 biases Stage 2. Fresh subagent or fresh worker per stage.

## Attribution

Two-stage-review pattern adapted from `obra/superpowers` (MIT) —
specifically the spec-reviewer / code-quality-reviewer split in their
subagent-driven-development skill. jjstack's version is simplified and
wires into `/work-order`, Quartermaster workers, and jjstack review
conventions.
