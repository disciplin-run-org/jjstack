---
name: writing-skills
description: >
  Meta-skill for authoring new jjstack skills. Covers file layout,
  frontmatter schema, trigger language, HARD-GATE usage, attribution
  conventions, testing the skill in-session, and the install-manifest
  integration. Use when creating a new skill, porting a skill from
  another ecosystem (gstack, superpowers, community), or converting a
  repeated workflow into a reusable skill. Trigger on: "write a skill",
  "new skill", "port this skill", "turn this into a skill",
  "skill-authoring", or when a repeated pattern deserves to be codified.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# writing-skills — How to author a jjstack skill

A jjstack skill is a single `SKILL.md` file in `skills/<name>/` with
YAML frontmatter and markdown body. Good skills are discovered
automatically via their description, invoked via `/<name>`, and
collaborate with other skills through explicit "Interaction with other
skills" sections.

Adapted from `obra/superpowers`' `writing-skills`.

## File layout

```
skills/
  <name>/
    SKILL.md             # required — the skill definition
    <supporting-file>.md # optional — references loaded at runtime
    <script>.sh          # optional — helpers the skill invokes
```

Naming:
- Directory and frontmatter `name` MUST match.
- Use kebab-case: `two-stage-review`, `verify-before-done`, not
  `twoStageReview` or `verify_before_done`.
- Keep names short enough to type as a slash command (`/<name>`).

## Frontmatter schema

```yaml
---
name: <kebab-case-name>
description: >
  <One paragraph. MUST include what the skill does, good fits, bad fits,
  and explicit trigger phrases. This is the only thing the agent sees
  when deciding whether to invoke the skill — invest in it.>
allowed-tools:
  - <list the tools the skill actually uses>
---
```

### Description: the most important field

The description is how the skill gets discovered. A bad description is a
skill no one finds. Required elements:

1. **What** — one sentence, active voice. "Runs two-pass code review."
2. **When to use** — conditions that select this skill over alternatives.
3. **When NOT to use** — conditions where another skill is better.
4. **Trigger phrases** — literal phrases the user says that should fire
   this skill. Include synonyms and voice-to-text alternates.

Example:
```yaml
description: >
  Review code in two passes: spec compliance first (did you build what
  was asked?), then code quality (is it good code?). Use after a
  subagent or worker completes a task, or before landing a non-trivial
  PR. Skip for trivial fixes (typo, version bump) — single-pass is
  fine. Trigger on: "two-stage review", "stage review",
  "spec-then-quality", "review against spec and quality".
```

### allowed-tools

List only tools the skill ACTUALLY uses. Over-broad permissions erode the
permission system's value. If the skill only reads files, don't list
Write. If the skill doesn't shell out, don't list Bash.

## Body structure

Every skill's body has these sections, in this order. Omit sections that
don't apply; don't invent new top-level sections without a reason.

```markdown
# <name> — <one-line tagline>

<Two-to-four-paragraph intro. What the skill does. Why it exists.
What problem it solves.>

## When to use

**Good fits:** <bulleted list>
**Skip for:** <bulleted list>

## The process

<Ordered steps or ASCII flow diagram. Keep it skimmable. Avoid Graphviz
DSL — jjstack convention is ASCII boxes.>

## <Core content sections>

<The actual meat of the skill — the rules, patterns, templates,
commands, whatever the skill teaches.>

## Interaction with other skills

- **`/<skill>`** — how this one relates. Does it replace, complement,
  extend, gate on, or conflict with that skill?

## Anti-patterns

<What mistakes this skill is trying to prevent. Concrete, not abstract.>

## Attribution

<If adapted from elsewhere: source, license, what was changed. If
original: just say so.>
```

## HARD-GATE

If the skill has a precondition that the agent will skip under pressure,
use a HARD-GATE block. See `references/hard-gate-convention.md` for
semantics and examples.

Use sparingly. A skill with three HARD-GATEs is probably three skills.

## Trigger phrases

The description's trigger phrases are how the agent decides to auto-fire
the skill. Collect them empirically:

1. Ship a draft of the skill.
2. Watch transcripts for sessions where the skill SHOULD have fired but
   didn't — what did the user say?
3. Add those phrases to the trigger list.
4. Watch for false positives — the skill firing when it shouldn't. Tighten
   the triggers that were too broad.

Start conservative, expand as you learn. An unfired skill is better than
a noisy one.

## Testing the skill in-session

Before committing, verify the skill works:

1. **Trigger test.** Say one of the declared trigger phrases in a fresh
   session. Does the skill get invoked via `Skill`? If not, the
   description is too vague.
2. **Invocation test.** Does `/<name>` work? If the skill has arguments
   (e.g. `/lean 20`), test with and without.
3. **Interaction test.** If the skill composes with others, actually
   compose them. A `/two-stage-review` skill is useless if it can't
   consume a `/work-order` output.
4. **HARD-GATE test (if applicable).** Try to bypass the gate. It should
   resist. If it lets you through, the gate text is too soft.

## Install-manifest integration

jjstack's `setup` script discovers skills automatically:

- Every directory under `skills/` with a `SKILL.md` gets a symlink in
  `~/.claude/skills/<name>`.
- No manual registration in `setup` is needed.
- The skill becomes available in every Claude Code session after running
  `./setup`.

If the skill adds a hook (PreToolUse, PostToolUseFailure, etc.):
- Put the hook script in `hooks/<name>.sh`.
- Edit `setup` to symlink it into `~/.claude/hooks/` and inject its
  settings.json entry. Match the existing idempotency pattern
  (`grep -q "<name>"` before adding).

If the skill needs a reference doc loaded at runtime:
- Put it in `references/<topic>.md`.
- Reference it from the skill body by path.
- Do NOT inline long reference material in the SKILL.md — skills should
  be skimmable.

## Attribution

If you're porting a skill from another ecosystem:
- License compatibility first. jjstack is MIT. Compatible: MIT, BSD,
  Apache-2.0. Check before copying.
- Credit the source in the Attribution section. Name the repo, the
  specific skill file, and the license.
- Note what you changed. jjstack-specific additions (monorepo
  conventions, Docker-first policy, Quartermaster integration) should
  be explicit so upstream can see what we added.

Example:
```markdown
## Attribution

Pattern adapted from `obra/superpowers` `<skill-name>` (MIT). jjstack
additions: <list>.
```

## Updating existing skills

- Small fixes (typos, better trigger phrases, clarified examples): commit
  directly with `fix(<skill-name>): <what>`.
- Breaking changes (renamed commands, changed frontmatter): bump VERSION
  minor. Note the breaking change in the commit.
- Removing a skill: remove the directory, update `setup` if it had
  hooks, update README. Add a note in the commit explaining why it's
  gone.

## Anti-patterns

- **Skill that describes a concept without a verb** — "/product-
  management" as a pure reference with no action verb is better as a
  reference file, not a skill. Skills DO things.
- **Skill with no trigger phrases** — undiscoverable.
- **Skill with a 3000-line body** — split it. Long skills are unread.
- **Skill that duplicates an existing one** — check first. `/office-hours`
  already covers brainstorming; don't add `/brainstorming`.
- **Skill without "Skip for" guidance** — the agent should know when NOT
  to fire. Omitting this causes noisy invocations.
- **Skill that uses Write without listing it in allowed-tools** — the
  skill will fail silently in restricted permission modes.
- **Skill body that copy-pastes the description** — waste of tokens; the
  agent already has the description.

## Reference to living exemplars

The best way to learn jjstack conventions is to read existing skills:
- `/work-order` — clean four-section template skill
- `/two-stage-review` — multi-phase skill with explicit gates
- `/lean` — mode-switching skill with a numeric argument
- `/verify-before-done` — HARD-GATE exemplar
- `/mcp-server` — complex multi-phase skill with supporting scripts

When in doubt, mirror whichever of these most resembles what you're
building.

## Attribution

Pattern adapted from `obra/superpowers` `writing-skills` (MIT).
jjstack-specific additions: install-manifest integration,
`references/` convention, monorepo HARD-GATE cross-reference,
attribution template.
