---
name: smart-simplify
description: >
  Automatically invokes the Anthropic code-simplifier plugin after significant code changes
  to clean up, clarify, and simplify recently modified code while preserving functionality.
  Triggers after: writing new features, refactoring, fixing bugs, or completing multi-file
  changes. Do NOT trigger for: config-only changes, documentation, single-line fixes,
  or when the user explicitly says "don't clean up".
disable-model-invocation: false
---

# Smart Simplify — Automatic Code Cleanup

## Purpose

Automatically invoke Anthropic's `/simplify` plugin after significant code changes
to keep the codebase clean and readable. This skill decides WHEN to simplify —
the plugin handles HOW.

## Decision Framework

After completing a coding task, evaluate whether simplification is warranted.

### INVOKE /simplify when:

1. **New feature implementation** — After writing 50+ lines of new code across
   multiple functions or files. Fresh code benefits most from a clarity pass.

2. **Complex refactoring** — After restructuring code, moving functions between
   files, or changing APIs. Refactoring often leaves artifacts.

3. **Bug fix with collateral changes** — When a fix required touching multiple
   files or adding workaround logic that could be simplified.

4. **Multi-file changes** — Any task that modified 3+ files. The more files
   touched, the higher the chance of inconsistency.

5. **After merging/resolving conflicts** — Conflict resolution often produces
   awkward code that needs cleanup.

### DO NOT invoke /simplify when:

1. **Config-only changes** — YAML, JSON, .env, docker-compose edits. No code to simplify.

2. **Documentation changes** — README, comments, docstrings only.

3. **Single-line fixes** — A one-line bug fix doesn't need a simplification pass.

4. **User said "don't clean up"** — Respect explicit opt-out.

5. **Already simplified this session** — Don't re-simplify code that was just simplified.

6. **Test-only changes** — Test code is meant to be explicit, not minimal.

## Invocation Protocol

When simplification IS warranted:

1. **Announce briefly:** "Running a simplification pass on the changes."
2. **Invoke:** `/simplify`
3. **The plugin handles the rest** — it reads recent changes, applies project
   standards from CLAUDE.md, and simplifies while preserving functionality.

## Integration with jjstack DNA

The simplifier will read CLAUDE.md and project conventions. If jjstack's coding DNA
is loaded (via `/python-coder`), the simplifier's output should already align with
those standards. If not, the coding DNA's self-review checklist serves as the
verification step after simplification.

## Graceful Failure

If `/simplify` is not available (plugin not installed):
1. **Do not error out.** Skip the simplification pass.
2. **Inform once per session:** "The code-simplifier plugin is not installed.
   Run `./setup` in your jjstack directory to install Anthropic plugins."
3. **Continue normally.** The code works without simplification — it's a polish step.
