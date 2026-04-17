---
name: state-doc
description: >
  Lightweight live-state document per working directory — a STATE.md that records
  what is currently in flight, what decisions were made, what's blocking, and what
  the next action is. Complements /checkpoint (snapshot at a moment) with a
  continuously updated pointer to "where we are right now." Use when starting a
  non-trivial work session, after a key decision, when hitting a blocker, or
  before handing off. Trigger on: "update state", "what's in flight", "current
  state of the work", "update STATE.md", "record this decision", or when
  returning to a project after a break.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# state-doc — Live STATE.md convention

`STATE.md` at the repo root is a single-file view of what is currently in
flight. It is not history (that's git), not a plan (that's a plan doc), not a
spec (that's LeanSpecs), and not a snapshot (that's `/checkpoint`). It is the
answer to "if I walked away and someone else sat down at this repo tomorrow,
what do they need to know right now?"

## Why it exists

Long-running sessions accumulate context that does not fit in any one CLAUDE.md,
plan, or commit message:

- The decision we made 20 minutes ago that isn't written down yet
- The thing we tried and ruled out so we don't loop back to it
- The reason we paused this branch to work on another
- The exact command that's blocked waiting for the user

Without STATE.md, this context lives only in the conversation. A fresh session,
a `/compact`, a `/clear`, a restart — all lose it. STATE.md survives.

## The shape

Keep it short. Four sections, no ceremony.

```markdown
# STATE

_Last updated: 2026-04-16 by quartermaster-qm_

## Now
<One paragraph. What we're actively doing this session.>

## Decisions
- <2026-04-16: decided X because Y. Alternative was Z — ruled out because ...>
- <2026-04-15: agreed to postpone the big refactor until after v0.5 ships>

## Blocked on
- <Exactly one thing, if anything. Who owns the unblock. What's needed.>

## Next
- [ ] <Concrete next action>
- [ ] <Next next action>
```

Add sections only when genuinely useful. Cut sections that are empty.

## Lifecycle

**Create** when starting non-trivial work in a repo that doesn't have one:
```bash
# From repo root
touch STATE.md
```

**Update** at these moments:
- After making a judgment call that doesn't belong in a commit message
- When hitting a blocker
- Before ending a session or handing off
- Before a `/compact` or `/clear` on a long session

**Prune** regularly:
- Decisions older than the current phase → move to a postmortem or delete
- Completed "next" items → delete (not check off — STATE is not a changelog)
- Resolved blockers → delete

**Delete** STATE.md when the phase/work is done and everything in it has
either shipped, moved to another doc, or become irrelevant.

## Rules

- **One file per repo**, at the repo root. Not per directory. Not per feature.
- **Keep it under 60 lines.** If it's growing, you're using it as a plan. Move
  planning to a plan doc and point to it.
- **Never write secrets** into STATE.md — it's checked in.
- **Never use it for history.** Git is history. STATE is the present tense.
- **Timestamp updates.** One line at the top: `_Last updated: YYYY-MM-DD_`.
- **Name decisions, not tasks.** Tasks go in plans. Decisions go here because
  they outlive the task that prompted them.

## Interaction with other artifacts

| Doc | Time horizon | What it answers |
|---|---|---|
| CLAUDE.md | Permanent | How this project works, always |
| LeanSpecs / product.json | Phase-long | What we're building |
| Plan docs (planning/*.md) | Phase-long | How we're building it |
| STATE.md | Days | Where we are right now |
| /checkpoint output | Moment | Exact state at one point in time |
| Commit messages | Permanent | What shipped |
| Memory (~/.claude/.../memory/) | Cross-session | User preferences, lessons |

STATE.md fills the gap between a plan (days-weeks) and a checkpoint (a moment).

## When to load STATE.md into context

- Start of every non-trivial session on the repo — read it first
- Before answering "what were we doing?" or "where did we leave off?"
- Before starting work a user hands off mid-task
- After a `/clear` or `/compact` — re-load to rebuild working context

## Relationship to `/checkpoint`

`/checkpoint` writes a one-time snapshot with full git state. STATE.md is
continuously edited. Use them together: STATE.md is what's alive right now;
`/checkpoint` is the "save point" you can resume from.

A common pattern:
1. Update STATE.md at key moments during the session
2. Run `/checkpoint` before a long break or context switch
3. On resume: read STATE.md first, `/checkpoint` second if more detail needed

## Quartermaster-specific usage

Quartermaster may maintain one STATE.md per active worker under the repo
root (e.g., `STATE.md` for the overall QA loop, referenced by each worker's
CLAUDE.md). Keep orchestrator state here — which worker is on what, what's
the current wave, what's the pending unblock. This survives `qm_restart` of
any individual worker.
