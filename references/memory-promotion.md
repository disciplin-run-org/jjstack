# Memory promotion — when a pattern earns permanence

Adapted from `pskoett/self-improving-agent`'s recurrence-based promotion
rule. Extends jjstack's typed memory system (user, feedback, project,
reference) with an explicit lifecycle: when does a memory graduate
from "episodic note" to "permanent guidance"?

## The problem

jjstack's memory system captures per-session learnings well but has no
convention for deciding when a memory should leave the memory dir and
become a rule in CLAUDE.md, a reference doc, or a project-wide policy.
The result: memory dirs accumulate semantically-similar entries that
should have been consolidated, and high-value insights stay buried in
per-project memory when they deserve global visibility.

Without a promotion rule:
- The same guidance gets saved three different ways across sessions
- CLAUDE.md stays out of date because no one notices when a memory has
  earned its place there
- Memories that recur are treated as new each time, losing the signal
  that "this keeps coming up."

## The rule

A feedback or project memory is a **promotion candidate** when:

1. The same underlying pattern has recurred **3+ times** (recurrence
   count), AND
2. The occurrences span **2+ distinct sessions or tasks** (so it's not
   just a single flaky session), AND
3. The guidance is **generalizable** beyond the immediate task (test:
   would a fresh Claude session on an unrelated task benefit from
   knowing this?).

When all three are true, the memory should be promoted — merged into
CLAUDE.md, a reference doc, or the system prompt — and the original
memory entries consolidated or deleted.

## Tracking recurrence

Extend the memory frontmatter with two optional fields:

```yaml
---
name: <existing>
description: <existing>
type: feedback           # or project, user, reference
pattern_key: <slug>      # stable identifier for the underlying pattern
recurrence_count: 3      # increment each time the same pattern is observed
last_seen: 2026-04-19    # date of most recent observation
---
```

`pattern_key` is a short, stable slug (e.g., `docker-first-always`,
`no-silent-catches`, `leanspecs-litmus-isolation`). When about to save a
new memory, grep the memory dir for existing entries with the same
`pattern_key`:

- **Match found** → update that entry: increment `recurrence_count`,
  update `last_seen`, append the new context to the body if it adds
  information. Do NOT create a duplicate.
- **No match** → create a new memory with `recurrence_count: 1`.

## The promotion workflow

When a memory's `recurrence_count` crosses the threshold (>= 3) and the
`last_seen` span covers 2+ sessions (check via git log or dates):

1. **Identify the promotion target.** Not every promoted memory goes to
   the same place.
   - Project-specific rule → the relevant CLAUDE.md (user or project
     level)
   - Generalizable technique → a reference doc under `references/`
   - User preference → stays in user-scope memory but gets a
     `promoted: true` flag indicating it's now canonical
   - Hook / automation opportunity → file an issue or write the hook

2. **Extract the rule.** Rewrite the memory body as a single rule or a
   short paragraph suitable for CLAUDE.md prose. Drop the per-incident
   context that made sense as a memory but becomes noise as a rule.

3. **Commit the promotion.** Add the rule to the target file in a
   commit labeled `docs(memory): promote <pattern_key>`. Include a
   pointer in the commit body to the memory entries being retired.

4. **Retire the memory entries.** Delete the originals (or mark with
   `promoted: <target-file>` and let a future cleanup sweep collect
   them). Update MEMORY.md to remove the index lines.

## When NOT to promote

Some high-recurrence patterns should stay in memory rather than graduate:

- **Project-specific details** that wouldn't help another project (API
  keys, internal URLs, team member preferences) — memory is the right
  place for these.
- **Evolving / uncertain patterns** — if the pattern keeps morphing, it
  isn't ready to become a rule yet. Let it stabilize.
- **Highly context-dependent guidance** that only applies under
  conditions too narrow to codify in CLAUDE.md prose.

Rule of thumb: if you can't write the promoted rule as a single
sentence another engineer would immediately understand, don't promote
it yet.

## The signal from `command-failures.jsonl`

The `error-detector.sh` hook (separate commit) populates
`~/.jjstack/command-failures.jsonl` with every failed Bash command.
This is the rawest source of recurrence signal. Periodically:

```bash
jq -r '.command' ~/.jjstack/command-failures.jsonl | sort | uniq -c | sort -rn | head
```

The top N patterns are candidate memories — either "the user keeps
making this mistake" (save as user memory) or "this command family
keeps breaking" (save as project memory) or "the agent keeps trying
a pattern that doesn't work here" (save as feedback memory).

Failures that appear 3+ times in the log meet the recurrence threshold
automatically.

## Interaction with other conventions

- **HARD-GATE** (`references/hard-gate-convention.md`) — promoted rules
  that must not be skipped can adopt the HARD-GATE syntax for stronger
  enforcement than soft prose.
- **CLAUDE.md** — primary promotion target for per-project rules.
  User-scope CLAUDE.md is the promotion target for cross-project rules.
- **MEMORY.md** — when a memory is retired after promotion, remove its
  index line. Keep MEMORY.md honest.

## Attribution

Pattern adapted from `pskoett/self-improving-agent`'s
recurrence-promotion rule: `Recurrence-Count >= 3` across `2+` tasks
triggers promotion. jjstack-specific additions include the
`pattern_key` convention, the `command-failures.jsonl` signal source,
and the four-target promotion map (CLAUDE.md / reference doc / flagged
memory / hook).
