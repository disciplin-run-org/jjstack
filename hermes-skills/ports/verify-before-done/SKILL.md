---
name: verify-before-done
description: >
  Mandatory pre-completion verification gate. Before declaring any task
  "done," explicitly runs the checks that prove the change actually works:
  tests, type checks, linters, health endpoints, UI smoke, and whatever
  else the task's spec or CLAUDE.md requires. Surfaces the verification
  output in the session so the claim is auditable. Use before saying
  "done," "complete," "shipped," or closing a work order. Trigger on:
  "verify before done", "am I done", "is this complete", "pre-completion
  check", or before declaring success on any non-trivial task.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
---

# verify-before-done — The "is this actually done?" gate

LLMs are optimistic. They will declare a task complete based on "the code
looks right" without running the tests, hitting the endpoint, or loading
the page. This skill makes verification a mandatory, visible step before
any completion claim.

## The iron rule

<HARD-GATE>
Do NOT say "done," "complete," "shipped," "fixed," "ready," or any
equivalent until the verification output for EVERY deliverable has been
captured in the session and each check has passed. A task without
verified output is not done — it is claimed done. Claims without evidence
are lies. This applies to EVERY task regardless of perceived simplicity.
</HARD-GATE>

## What counts as verification

Verification is a command or observation that produces evidence captured
in the session transcript so it is auditable.

**Acceptable:**
- `pytest` output showing all green
- `tsc --noEmit` output showing zero errors
- `curl /health` returning 200 with expected payload
- `docker compose logs service` showing expected startup line
- Browser showing expected page state
- Diff output showing the intended change

**Not acceptable:**
- "The code looks right" — read is not verification
- "Should work" — hypothesis is not verification
- "The test exists" — existence is not passing
- "CI will check it" — async promise is not verification of this session
- "The build succeeded last time" — staleness is not verification

## The process

```
┌─────────────────────────────────┐
│ Task reports implementation done│
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ List every deliverable + its    │
│ verification command            │
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ Run each verification command   │
│ Capture output in session       │
└────────────────┬────────────────┘
                 ▼
         ┌───────┴───────┐
         │ All green?    │
         └───┬───────┬───┘
         yes │       │ no
             ▼       ▼
         ┌─────┐  ┌──────────────┐
         │Done │  │Fix, re-verify│
         └─────┘  └──────────────┘
```

## What to verify

Minimum set for any code change:

1. **Tests.** Run the project's test suite for the modified surface. Show green output.
2. **Type / lint.** Run the project's type checker and linter on the diff.
3. **Smoke the feature.** If UI: load it. If API: hit the endpoint. If script: run it.
4. **Spec-specific verify steps.** If from a `/work-order`, run every command in Verify section.

## When the verification fails

1. Read the failure output.
2. If caused by your change: fix and re-verify. Do not declare done.
3. If pre-existing: surface it explicitly with evidence (git blame/history). Ask the user
   whether to fix, defer, or land despite it. Do not land silently.
4. If unclear: bisect — revert to HEAD, run the check. If it passes at HEAD, your change caused it.

## Interaction with other skills

- **`/work-order`** — every work order has a Verify section. This skill runs that section.
- **`/two-stage-review`** — Stage 1 includes running verify steps. This skill is the
  standalone version for cases without a work order.
- **`/lean`** — lean mode says "run tests once." This skill refines that: run verify once,
  fix once if failed — but never SKIP verify. Lean does not mean optimistic.

## Minimum viable output shape

```
## Pre-completion verification

Task: <one-line summary>

### Deliverables + verify
- [x] <deliverable 1> — `pytest tests/foo -v` → 12 passed in 1.3s
- [x] <deliverable 2> — `curl -sf http://localhost:8002/health` → 200
- [x] <deliverable 3> — `tsc --noEmit` → no errors

### Done
YES — all verify steps green at <short-sha>.
```

If any step fails, the block says NO with the failure captured. Do not
proceed to "done" claims until the block says YES.

## Attribution

Pattern adapted from `obra/superpowers` `verification-before-completion` (MIT).
Additions: work-order integration, lean-mode compatibility, failure-bisection guidance.
