# HARD-GATE convention for jjstack skills

A HARD-GATE is an explicit, non-negotiable stop in a skill that prevents
the agent from advancing to the next phase until a specific condition is
met. Adapted from `obra/superpowers` (MIT).

## Why it exists

LLMs default to "helpful forward motion." When a skill says "please get
user approval before writing code," the agent will often interpret
ambiguous user replies ("sounds good, let's see it") as approval and rush
into implementation. Soft gates get rationalized past.

A HARD-GATE makes the stop mechanical: the agent must produce a specific
artifact (design doc, spec, work order, failing test) before it is allowed
to proceed. No rationalization path exists because the gate is syntactic,
not semantic.

## Syntax

Use the literal tag pair in the skill body:

```markdown
<HARD-GATE>
Do NOT <forbidden action> until <required artifact> exists AND <condition>.
This applies to EVERY invocation regardless of perceived simplicity.
</HARD-GATE>
```

Rules for the gate body:
- **Forbidden action** — verb + object. ("write any code," "invoke
  implementation skill," "send the work order," "merge the PR")
- **Required artifact** — something the agent can check for. ("a design
  doc at `docs/...`", "a failing test output", "user has said 'approved'
  in chat", "spec file committed")
- **No exceptions clause** — "EVERY invocation regardless of perceived
  simplicity" prevents the "this case is different" rationalization.

## When to add a HARD-GATE

Add one when the skill has a phase the agent will skip under pressure and
where skipping causes expensive downstream failure.

**Good candidates:**
- Design-before-implementation (brainstorming, office-hours-style skills)
- Failing-test-before-implementation (TDD skills)
- Spec-compliance-before-quality-review (two-stage review)
- Verify-before-done (completion gates)
- Approval-before-destructive-action (ship, land-and-deploy)

**Bad candidates:**
- Soft stylistic preferences ("please be concise") — not a gate, a rule
- Advisory checkpoints where the agent should use judgment
- Multi-phase flows where each phase is already structurally enforced

## Example: adding a HARD-GATE to `/work-order`

Before:
```markdown
## Usage

When a user asks to delegate a task, draft the work order in this shape
before sending it.
```

After:
```markdown
## Usage

<HARD-GATE>
Do NOT send a work order (via qm_send, Agent, PR body, or any other
channel) until the Context, Deliverables, Verify, and Done-when sections
are all present. A work order missing any of these four sections is a
defect. This applies to EVERY work order regardless of perceived
simplicity.
</HARD-GATE>

When a user asks to delegate a task, draft the work order in this shape
before sending it.
```

## Example: adding a HARD-GATE to a TDD skill

```markdown
<HARD-GATE>
Do NOT write production code until a failing test exists AND the failure
message has been captured in the session. If the test passes before
implementation, the test is wrong — fix the test first. This applies to
EVERY feature, bug fix, and refactor regardless of perceived simplicity.
</HARD-GATE>
```

## What the agent should do when it sees a HARD-GATE

1. Treat it as a mandatory precondition, not advice.
2. Before taking the forbidden action, produce or verify the required
   artifact.
3. If the user explicitly overrides ("I know, skip the gate this once"),
   proceed — user override always wins — but surface the override in
   output so it's visible in the transcript.
4. Never interpret ambiguous user replies as implicit override.

## What the agent should NOT do

- Paraphrase the gate into a soft suggestion in output.
- Proceed because "this case is trivial."
- Proceed because "the user seemed to agree."
- Proceed because the artifact "basically exists in the conversation."

## Interaction with the injection-guard hook

Skills that describe HARD-GATE patterns may reproduce gate text that uses
imperative language ("do NOT," "you must"). This can accidentally match
the injection-guard hook's role-reprogramming and imperative-tool-invocation
patterns. If a skill file is blocked on write:

- Move the example gate text inside a fenced code block (it is still read
  by the agent as part of SKILL.md).
- OR rephrase examples to omit imperative framing outside the gate tag.

## Attribution

Pattern from `obra/superpowers` brainstorming skill's `<HARD-GATE>` block.
jjstack adopts the same tag syntax so skills are portable across both
ecosystems.
