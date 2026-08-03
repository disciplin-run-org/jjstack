---
name: lean
description: >
  Cost-lean mode: sets an explicit tool-call budget and strict minimum-turn
  execution rules for cost-sensitive flows (QA loops, agent pipelines, batch
  jobs). No polishing passing code, no iteration loops on the same failure,
  no speculative refactoring. Use when token or wall-time cost matters more
  than thoroughness. Trigger on: "lean mode", "cost mode", "tool budget",
  "minimum turns", "be cheap", "cost-lean", or before any agent pipeline
  where every call counts.
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
loops where every tool call compounds across hundreds of iterations.

Based on measured benchmarks where a 20-call budget config beat a 50-call
structured config by 17.4% on the same three challenges.

## What changes when you're in lean mode

**Hard budget.** The operator sets an explicit tool-call cap per task:

- `/lean 20` — ultra-lean, one-shot execution. For simple fixes, single-file tasks.
- `/lean 50` — default lean. For multi-file changes, non-trivial bugs.
- `/lean 100` — generous lean. For multi-hour sessions. Still enforces the rules below.

If no number is passed, default to 50.

**Execution rules (stricter defaults):**

1. **Read ALL relevant files including the test file first.** The test defines
   what passes. Do not start writing until you have the whole surface mapped.

2. **Write the complete solution in one pass.** Not incrementally. Plan the
   full edit, then apply it. Multiple rounds of Edit on the same file signals
   you didn't plan well enough — stop and re-read.

3. **Run tests / verify once.** If pass: stop immediately. Do not re-verify,
   do not add "one more test," do not refactor.

4. **Never iterate more than once on the same failure.** Failed → read error
   → fix once → retest. If it fails the same way again, stop and rethink the
   mental model. Do not loop.

5. **Never polish passing code.** No rename passes, no docstring additions,
   no comment tidying, no "while I'm here" changes. Done means done.

6. **No speculative files.** Do not create helper modules, utility classes, or
   shared abstractions unless the task requires them.

7. **Output is code and verification only.** No explanation, no summary, no
   "here's what I changed" narrative unless explicitly requested.

## When to use lean mode

**Good fits:**
- QA loops: generate → run → fix → retest across dozens of behaviors
- Batch code generation: many small similar files
- Agent pipelines where the same shape will run >10 times
- Any session where cost compounds per iteration

**Bad fits:**
- Exploratory architectural work (debate is the point)
- Root-cause investigation where breathing room matters
- Anything with a single high-judgment decision

For those, use default mode — the thoroughness is worth the tokens.

## How to enter lean mode

Type `/lean [budget]` at the start of a task. Rules apply until you end
the task or explicitly exit with "exit lean" / "back to normal mode."

## How to exit lean mode

Say "exit lean," "back to normal," or start a fresh unrelated task. Lean mode
is session-scoped, not persistent.

## Interaction with other skills

- **`/work-order`** — work orders drafted while in lean mode should include the
  budget in the Context section so the recipient inherits it.
- **`/verify-before-done`** — lean does not mean skip verification. Run once,
  fix once if failed, but never skip.
- **`/simplify-code`** — do NOT run simplify passes while in lean mode.
  Simplify is a polish pass; that violates rule 5.

## Honest trade-off

Lean mode trades thoroughness for cost efficiency. It is the wrong default.
It is the right mode when output volume compounds across many similar tasks
and the per-task judgment bar is low. Pick deliberately.

## Attribution

The 20/50/100 budget pattern and one-shot-write rules are adapted from
`claude-token-efficient` (MIT, drona23) with modifications for multi-agent
workflows.
