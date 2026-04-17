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

Adapted from `obra/superpowers`' `verification-before-completion`.

## The iron rule

<HARD-GATE>
Do NOT say "done," "complete," "shipped," "fixed," "ready," or any
equivalent until the verification output for EVERY deliverable has been
captured in the session and each check has passed. A task without
verified output is not done — it is claimed done. Claims without evidence
are lies. This applies to EVERY task regardless of perceived simplicity.
See references/hard-gate-convention.md.
</HARD-GATE>

## What counts as verification

Verification is a command or observation that produces evidence. The
evidence must be captured in the session transcript so the user (or a
reviewer reading the log later) can audit the claim.

**Acceptable:**
- `pytest` output showing all green
- `tsc --noEmit` output showing zero errors
- `curl /health` returning 200 with expected payload
- `docker compose logs service` showing the expected startup line
- Browser navigation (via `/browse`) showing the expected page state
- Screenshot from `/browse` with the expected element visible
- Diff output showing the intended change

**Not acceptable:**
- "The code looks right" — read is not verification
- "Should work" — hypothesis is not verification
- "The function returns X" — static reasoning is not verification
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
         └─────┘  │same command  │
                  └──────────────┘
```

## What to verify

Minimum set for any code change:

1. **Tests.** Run the project's test suite for the modified surface.
   Show green output. Never say "tests pass" without the output.
2. **Type / lint.** Run the project's type checker and linter on the
   diff. Show zero errors.
3. **Smoke the feature.** If it's a UI change, load it in a browser. If
   it's an API, hit the endpoint. If it's a script, run the script. If
   it's a Docker service, check health.
4. **Spec-specific verify steps.** If the task came from a `/work-order`,
   run every command listed in the work order's Verify section. All
   must pass.

Additional checks when applicable:
- **CLAUDE.md rules** — grep for known anti-patterns (`catch(() => {})`,
  `except: pass`) if the change involves error handling
- **Regressions** — run adjacent tests not just the one that motivated
  the change
- **Docker build** — if the change touches Dockerfile or dependencies,
  rebuild the image
- **Database migrations** — if a migration changed, run it up-and-down on
  a throwaway DB
- **Visible state in UI** — don't trust the network tab; look at the
  rendered page

## When the verification fails

This is the important case. The agent's instinct is to say "the test is
flaky, I'll run it again" or "this is unrelated, not my problem." Both
are wrong in the context of this skill.

1. Read the failure output.
2. If the failure is caused by your change, fix and re-verify. Do not
   declare done.
3. If the failure is pre-existing, surface it explicitly: "This failure
   existed before my change — here's the git blame / history proving it."
   Then ask the user whether to fix it, defer it, or land despite it. Do
   not land silently assuming it's fine.
4. If you cannot determine whether the failure is caused by your change,
   bisect: revert to HEAD, run the check, see if it passes. If it passes
   at HEAD, your change caused the failure.

## Interaction with other skills

- **`/work-order`** — every work order has a Verify section. This skill
  runs that section.
- **`/two-stage-review`** — Stage 1 includes running verify steps. This
  skill is the standalone version for cases without a work order.
- **`/ship`** — ship should already be running verifications. This skill
  applies before invoking ship for non-ship contexts (e.g., closing an
  iris-qa test loop, declaring a debugging session done).
- **`/lean`** — lean mode says "run tests once." This skill refines that:
  run verify once, and if it fails fix once — but do not SKIP verify.
  Lean does not mean optimistic.
- **`/investigate`** — the fix from an investigation is not done until
  the original failure is verified fixed. This skill is the gate.

## Anti-patterns

- **"The tests pass on my machine"** — run them in the actual target
  environment. For this monorepo, that means Docker (`feedback_always_docker`
  in memory).
- **"The CI will catch it"** — CI is a backstop, not primary verification.
  Verify locally first.
- **"I'll verify after the commit"** — commits without verification leave
  broken code on the branch. Verify, then commit.
- **"I ran the unit test, the integration test is too slow"** — if the
  task changes integration surface, the integration test is the required
  verification. Slow is not an exemption.
- **Running verification in a different session and pasting results** —
  the session transcript is the audit record. Verify in-session.

## Minimum viable output shape

When running this skill, produce a block like:

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

Pattern adapted from `obra/superpowers` `verification-before-completion`
(MIT). jjstack additions: Docker-first verification (per monorepo's
feedback_always_docker rule), work-order integration, lean-mode
compatibility, failure-bisection guidance.
