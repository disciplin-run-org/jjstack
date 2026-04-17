---
name: lean
description: >
  Cost-lean mode: sets an explicit tool-call budget and strict minimum-turn
  execution rules for cost-sensitive flows (QA loops, ralph-loop, agent
  pipelines, batch jobs). No polishing passing code, no iteration loops on
  the same failure, no speculative refactoring. Use when token or wall-time
  cost matters more than thoroughness. Trigger on: "lean mode", "cost mode",
  "tool budget", "minimum turns", "be cheap", "cost-lean", or before a QA
  loop, ralph-loop, or any agent pipeline where every call counts.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# lean — Cost-lean execution mode

Turns on strict minimum-turn rules for the rest of the session. Intended for
loops where every tool call compounds across hundreds of iterations: the
QA loop (generate → run → fix → retest), ralph-loop, Quartermaster worker
pipelines, batch code generation.

Based on measured benchmarks from `claude-token-efficient` (drona23) where a
20-call budget config beat a 50-call structured config by 17.4% on the same
three challenges, same harness, same model.

## What changes when you're in lean mode

**Hard budget.** The operator sets an explicit tool-call cap per task:

- `/lean 20` — ultra-lean, one-shot execution. For simple QA tests, single-file
  fixes, stateless generators.
- `/lean 50` — default lean. For multi-file changes, non-trivial bugs.
- `/lean 100` — generous lean. For multi-hour worker sessions. Still enforces
  the rules below, just more headroom.

If no number is passed, default to 50.

**Execution rules (stricter than jjstack defaults):**

1. **Read ALL relevant files including the test file first.** The test defines
   what passes. Do not start writing until you have the whole surface mapped.

2. **Write the complete solution in one pass.** Not incrementally. Plan the
   full edit, then apply it. Multiple rounds of Edit on the same file is a
   signal you did not plan well enough — stop and re-read.

3. **Run tests / verify once.** If pass: stop immediately. Do not re-verify,
   do not add "one more test," do not refactor.

4. **Never iterate more than once on the same failure.** Failed → read error
   → fix once → retest. If it fails the same way again, stop and rethink the
   mental model. Do not loop.

5. **Never polish passing code.** No rename passes, no docstring additions,
   no comment tidying, no "while I'm here" changes. Done means done.

6. **No speculative files.** Do not create helper modules, utility classes, or
   shared abstractions unless the task requires them. Three similar lines
   beat a premature abstraction every time.

7. **Output is code and verification only.** No explanation, no summary, no
   "here's what I changed" narrative unless explicitly requested. The diff is
   the output.

## When to use lean mode

**Good fits:**
- QA loops: iris-qa generate → run → fix → retest across dozens of behaviors
- ralph-loop: recurring tasks where verbosity compounds per iteration
- Quartermaster worker pipelines: each worker runs the same shape repeatedly
- Batch code generation: many small similar files
- Any session where the same shape will run >10 times

**Bad fits:**
- Exploratory architectural work (debate is the point)
- `/office-hours`, `/plan-ceo-review`, `/plan-eng-review` (deliberation-heavy)
- `/investigate` where root-cause hunting needs breathing room
- Anything with a single high-judgment decision

For those, use default jjstack mode — the thoroughness is worth the tokens.

## How to enter lean mode

Type `/lean [budget]` at the start of a task. The rules apply until you end
the task or explicitly exit with "exit lean" / "back to normal mode."

Workers spawned via Quartermaster can be sent into lean mode by prefacing
the qm_send text with `/lean 20` (or the chosen budget).

Agent calls can be sent into lean mode by including the budget and rules in
the prompt's Context section (per `/work-order`).

## How to exit lean mode

Say "exit lean," "back to normal," or start a fresh unrelated task. Lean mode
is session-scoped, not persistent — it never bleeds into unrelated work.

## Interaction with other skills

- **`/work-order`** — work orders drafted while in lean mode should include the
  budget in the Context section so the recipient inherits it.
- **`/qa`**, **`/qa-only`** — already reasonably scoped, but lean mode tightens
  them further for bulk runs.
- **`/careful`**, **`/guard`** — orthogonal. Safety rules still apply in lean
  mode; lean does not bypass destructive-command warnings.
- **`/simplify`** — do NOT run simplify passes while in lean mode. Simplify is
  a polish pass. That violates rule 5.

## Honest trade-off

Lean mode trades thoroughness for cost efficiency. The benchmark savings
come from:
- Fewer re-reads (rule 1)
- Fewer incremental edits (rule 2)
- Fewer retries on the same failure (rule 4)
- No polish passes (rule 5)

It is the wrong default. It is the right mode when output volume compounds
across many similar tasks and the per-task judgment bar is low. Pick
deliberately.

## Attribution

The 20/50/100 budget pattern and one-shot-write rules are adapted from
`claude-token-efficient` (MIT, drona23) with modifications for jjstack's
multi-agent workflows.
