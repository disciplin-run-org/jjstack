---
name: plan-edit
description: >
  Read and edit a plan without re-reading the wall. Treats a plan as a
  sectioned file, not chat text: render it color-coded at terminal width
  (view), jump to one section (toc + show N), edit surgically, then show
  only the colored track-changes delta (diff) instead of re-printing pages.
  revoice rewrites a plan tighter and in Jesper's Voice DNA with the diff as
  a fidelity audit. All deterministic except the revoice rewrite. Never emits
  red (unreadable on the black terminal) and never emdash. Use when iterating
  on a multi-page plan, after a tweak, or to tighten a plan in your voice.
  Trigger on: "edit the plan", "tweak the plan", "change the plan", "show plan
  changes", "track changes on the plan", "what changed in the plan", "read
  section N of the plan", "tighten the plan", "rewrite the plan in my voice",
  "plan-edit". Skip for: writing a brand-new plan from scratch (use plan mode),
  reviewing a plan's content for quality (use the plan-*-review skills), or
  tracking live work status (use /state-doc).
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
---

# plan-edit - edit plans, render the whole plan in the native panel

Plan mode renders the plan inline, so one tweak forces a full re-scan. This
skill keeps the plan in a file, edits it surgically, and renders the whole
plan in Claude Code's native plan panel - in color, no fold - with only the
last edit highlighted.

The helper is `~/.claude/skills/jjstack/bin/jjstack-plan`, on PATH as
`jjstack-plan`. With no FILE it resolves THIS session's plan from the session
transcript (`$CLAUDE_CODE_SESSION_ID`), not the global-newest file in the flat,
shared `~/.claude/plans/`. It prints the resolved path; if it has to guess
global-newest it prints a warning. Pass a path to be certain.

## Rendering: the native plan panel, never Bash

Claude Code's plan panel renders the plan *file* in color and never folds.
That is the view surface. **Do NOT run `view`/`diff` through the Bash tool to
show the user** - the harness folds the output into a "+N lines" widget and
strips the ANSI. To put the plan on screen, drive the native panel:

1. `EnterPlanMode` - binds this session's plan file.
2. `jjstack-plan clear <file>` - restore clean text (drop any leftover
   highlight bold from the prior render).
3. `jjstack-plan highlight <file>` - first reflows the plan (joins hard-wrapped
   lines into one line per paragraph so the panel fills the screen width, not a
   narrow column), then bolds the spans changed since the previous version.
   Non-cumulative: it diffs against the last `highlight` and advances the
   baseline, so only the latest edit is bold. First run reflows and bolds
   nothing. (`jjstack-plan reflow` does the de-wrap on its own.)
4. `ExitPlanMode` - the panel renders the whole plan, in color, last edit bold.

Markdown has no inline color, so the in-panel highlight is **bold**. For true
green/magenta word-level track-changes the user runs `! jjstack-plan diff
<file>` in their own terminal.

## On invocation - what `/plan-edit` does

1. `EnterPlanMode`.
2. `jjstack-plan clear` then `jjstack-plan highlight` (no arg - resolves this
   session's plan; first time bolds nothing and sets the baseline).
3. `ExitPlanMode` - the full plan renders in the native panel. Ask what to
   change.

## The edit loop

For each change the user names:

1. `jjstack-plan clear <file>` - restore clean text so edits land on plain
   markdown, not on last round's bold.
2. `Edit` the one section in Jesper's voice. Never rewrite the whole file.
3. `jjstack-plan highlight <file>` - bold only this edit's delta; the prior
   highlight is cleared.
4. `EnterPlanMode` then `ExitPlanMode` - re-render the whole plan in the panel.
   Only the new change is bold.

Keep the plan in JJ Voice DNA: write new and edited text in his voice
(conclusion first, compressed, short dash, Oxford comma, no superlatives, no
meta-commentary). Do NOT re-voice unchanged text each round - that highlights
everything and risks fidelity. The `!` CLI keeps the color jobs the panel
cannot do: `diff` (green/magenta word-level), `lint`, `revoice`.

## When to use

**Good fits:**
- Iterating on a multi-page plan: render it, tweak one section, re-render.
- Showing the user the whole plan with only the latest change highlighted.
- Tightening a plan, or putting it in Jesper's voice, without losing fidelity.

**Skip for:**
- Writing a brand-new plan from scratch - that is plan mode.
- Judging a plan's content or strategy - that is the `plan-*-review` skills.
- Tracking live work status - that is `/state-doc`.

## revoice - the one inference step

`jjstack-plan revoice <file> [section]` ensures a baseline, then emits the
Voice DNA plus the rewrite target. You then:

1. Read the emitted Voice DNA rules.
2. Rewrite the target in place with the `Edit` tool, in Jesper's voice.
3. Run `jjstack-plan diff <file>` so the user audits every change.
4. Run `jjstack-plan lint <file>` to check the mechanical rules.
5. `accept` once the user signs off.

**Fidelity is the hard rule: re-voice and compress, never summarize.** Every
fact, section, and decision survives the rewrite. A summary is the failure
mode. The diff is the audit surface - if a fact vanished, the diff shows it.

Voice DNA source:
`/home/jesper/PycharmProjects/jesper-jurcenoks-ai-personalizations/voice-dna/Jesper Jurcenoks Voice DNA Final.md`
(override with `$JJSTACK_VOICE_DNA`).

## Color and voice rules - enforced in code, not just convention

- **Never red - CLI.** The palette is green (adds), bright magenta +
  strikethrough (deletes), bright cyan (headings), bright yellow (emphasis),
  dim (context). `scrub_red()` strips red SGR codes from all CLI output.
- **Native panel colors are the theme's, not the skill's.** The panel colors
  code blocks and links from the active Claude Code theme; there is no
  per-element color setting, and neither the skill nor the plan content can
  change it. Code blocks and links are left intact (they aid readability) even
  though the theme renders some of their tokens red. A true recolor is a
  harness-level change: a custom theme in `~/.claude/themes/` or remapping the
  terminal's `red`, both of which fix red everywhere, not just in plans.
- **Never emdash.** `lint` flags any emdash; the Voice DNA mandates short dash.
- **Color degrades gracefully.** With `NO_COLOR` or no TTY, adds show as
  `[+...+]` and deletes as `[-...-]` - track changes stay legible.
- **`lint` is deterministic.** It flags emdash, "but", superlatives,
  contractions, and red ANSI. Inference writes the prose; code checks it.

## Interaction with other skills

- **`/state-doc`** - STATE.md is present-tense status; a plan doc is the plan.
  Complementary, not overlapping.
- **`plan-ceo-review`, `plan-eng-review`, `plan-design-review`** - they critique
  a plan's content and score it. This skill reads and edits the plan. Use them
  to judge, use this to navigate and revise.
- **`/writing-skills`** - the meta-skill this one was authored under.

## Anti-patterns

- **Re-printing the whole plan after a tweak.** That is the pain this skill
  exists to kill. Show the `diff`, not the document.
- **Rewriting the whole file in one `Edit`.** Edit the one section that changed.
  Surgical edits keep the diff small and reviewable.
- **Letting `revoice` summarize.** Tightening drops words, never facts. If the
  diff shows a decision disappearing, that is a bug in the rewrite, not a win.
- **Hand-formatting colored plan output.** Let the helper render it - it is the
  only thing that guarantees no red.

## Attribution

Authored per `/writing-skills` conventions. Voice rules and the `revoice` target
come from Jesper's Voice DNA repo (`jesper-jurcenoks-ai-personalizations`). The
diff engine is Python stdlib `difflib`; no external dependencies.
