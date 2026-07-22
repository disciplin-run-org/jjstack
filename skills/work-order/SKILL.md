---
name: work-order
description: >
  Structured work-order template for delegating concrete work to a worker, sub-agent,
  PR description, or plan item. Forces an explicit Context / Deliverables / Verify /
  Done shape that leaves no ambiguity about what "done" means. Use any time you're
  about to send a non-trivial task to someone else (human, worker, sub-agent) or
  write a task in a plan. Trigger on: "write a work order", "draft a task for", "send
  this to <worker>", "task for <agent>", "structured task", or before invoking Agent
  with a non-trivial prompt.
  Do NOT trigger for: executing a task yourself (just do the work), a TDD/QA
  delegation to iris-qa (use /qa-build-loop), or status updates about an existing
  work order (no skill — that is orchestration, not authoring).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# work-order — Structured delegation template

A good work order is three things at once: enough context that the recipient can
make judgment calls, a precise deliverable list so "done" is unambiguous, and a
verification step so neither side has to argue about whether it's finished.

This skill produces work orders in a consistent shape. Use it for:

- Quartermaster `qm_send` messages to workers
- `Agent` tool prompts for non-trivial sub-agent tasks
- Plan items in `/plan-eng-review`, `/office-hours` outputs
- PR bodies and GitHub issue descriptions
- Handoffs between sessions or between humans

## The shape

Every work order has four sections. Missing any one is a defect.

```
## Context
<Why this matters. What has already been tried or ruled out. Links to prior work,
related specs, related bugs. Enough that the recipient can make judgment calls
instead of just following narrow instructions.>

## Deliverables
<Concrete list of what must exist when the work is done. Files, commits, PRs,
test results, deployed state. Use a checklist. No verbs like "investigate" —
the deliverable is the output of the investigation, not the investigation.>

## Verify
<The exact command, query, or observation that proves each deliverable is real.
"Run pytest and show all green." "Curl /health and show 200." "Show the diff."
If you can't write this, the deliverable is underspecified.>

## Done when
<Binary pass/fail criteria. "All tests green AND branch merged to main AND
CLAUDE.md reflects new rule." No "looks good" — no judgment calls at the gate.
Default gate: DONE = done-done — the canonical 10-rung Definition of Done in
`references/definition-of-done.md` (version-controlled source of truth;
mirrored in global CLAUDE.md). If a rung genuinely doesn't apply, say so in
the order; the recipient reports "done N/10" naming missing rungs otherwise.>
```

## Optional sections

Add only when relevant:

- **Skill to invoke** — e.g. `/python-coder`, `/investigate`, `/qa`. Tells the
  recipient which specialized workflow to run.
- **Out of scope** — explicit non-deliverables. Prevents scope creep. Use when
  the recipient is likely to wander ("also don't touch the auth module").
- **Links** — prior PRs, specs, memory notes, error logs.
- **Constraints** — hard requirements: "must not require a schema migration,"
  "must be backwards compatible with v0.4 clients."

## Anti-patterns

**Vague**: "Fix the bug in spec_create." Which bug? Fix how? Done when?

**Over-specified**: writing the exact Python code for the recipient to paste.
The recipient is a specialist — give them the outcome, not the keystrokes.

**No verify step**: "Make it work." You're asking the recipient to declare
victory unilaterally. The verify step is the contract.

**Mixed deliverable and process**: "Investigate and fix the performance issue
and write a postmortem." Three work orders. Split them.

**Diagnosis as deliverable**: a work order whose premise is "X is broken, fix
it" must carry *reproduced evidence of X failing through the real path* — not
the author's diagnosis. "test_read omits the `product` field" is a diagnosis;
the parsed response showing no `product` key is evidence. A WO built on an
unverified diagnosis dispatches a worker onto fabricated work. If the failing
evidence won't materialize when you try to reproduce it, there is no work order
— the bug was in your investigation, not the code. (See
`references/root-cause-analysis.md` Rule 3: no action before a `verified` root.)

**Infinite context**: dumping every related file. The recipient reads selectively;
give them the hooks to find what they need, not the entire codebase.

## Minimum viable work order

For trivial tasks, a one-liner with verify is fine:

```
Bump version in pyproject.toml to 0.5.2. Verify: `grep version pyproject.toml`
shows 0.5.2. Done when: committed to main.
```

The four-section shape is for anything non-trivial (>15 minutes of work, or
any task a specialist worker will run in a long-lived session).

## Usage

<HARD-GATE>
Do NOT send a work order (via qm_send, Agent, PR body, or any other
channel) until the Context, Deliverables, Verify, and Done-when sections
are all present. A work order missing any of these four sections is a
defect. This applies to EVERY work order regardless of perceived
simplicity. Additionally: a work order whose premise is "X is broken"
is a defect unless it cites reproduced evidence of X failing through
the real path (not a diagnosis) — see the "Diagnosis as deliverable"
anti-pattern. See references/hard-gate-convention.md for the semantics
of this tag.
</HARD-GATE>

When a user asks to delegate a task, draft the work order in this shape
*before* sending it. Show the user the draft, adjust based on their feedback,
then deliver it (via `qm_send`, `Agent`, PR body, etc.).

If the user skips this skill and writes a vague task directly, you may still
restructure their request into this shape before sending — but flag that you
did so, so they can correct.

## Related skills

- `/office-hours` — produces higher-level goals that work orders implement
- `/plan-eng-review` — reviews plans composed of work orders
- `/ship` — consumes a done work order and produces the PR
