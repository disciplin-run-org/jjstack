---
name: worktrees
description: >
  Git worktree workflow for parallel development. Creates isolated working
  directories so the main tree stays on its branch while experimental
  work, long-running subagents, or parallel features proceed on separate
  branches without merge conflicts, stash juggling, or branch-switching
  churn. Use when starting work that will run in parallel with the main
  session, or when spawning a subagent that needs its own isolated tree.
  Trigger on: "new worktree", "isolate this work", "parallel branch",
  "worktree for X", "spawn subagent on own branch", or when Conductor-style
  parallel workstreams are appropriate.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# worktrees — Parallel branches via git worktree

Git worktrees give you multiple checked-out branches of the same repo in
separate directories. Unlike clones, they share the same `.git` object
store (cheap) and unlike branch-switching, they let work proceed on
multiple branches simultaneously with no stash churn.

This skill codifies jjstack's worktree workflow so parallel subagents,
experimental branches, and long-running work don't step on the main tree.
Adapted from `obra/superpowers`' `using-git-worktrees`.

## When to use

**Good fits:**
- Spawning a subagent or Quartermaster worker that will edit files for
  >10 minutes — give it its own tree so main-session edits don't collide
- Experimenting with a refactor while keeping the main tree on a
  production-ready branch
- Running `/ship` on branch A while starting `/plan-eng-review` on branch B
- Running a QA loop on branch A while writing code on branch B
- Conductor-style parallel workstreams on different features

**Skip for:**
- Single-file edits expected to finish in minutes — branch-switch is cheaper
- Throwaway exploration — just make a scratch branch in the main tree
- Work that will never diverge from the current branch

## Directory convention

```
~/PycharmProjects/<repo>/           # main tree, usually on master/main
~/PycharmProjects/<repo>-wt/
  feature-x/                         # worktree on branch feature-x
  subagent-2026-04-16-qa-fix/        # ephemeral worktree for a subagent
  bug-investigation-#123/            # worktree for a debugging session
```

Rules:
- All worktrees for a repo live under `<repo>-wt/` as a sibling to the
  main tree. Never nest worktrees inside the main tree (`git worktree add`
  will allow this but it confuses tools like `find`, `rg`, IDE indexers).
- Name worktree directories after the branch, with an optional date or
  context suffix for ephemeral work.

## Commands

### Create a worktree

```bash
git -C <repo> worktree add ../<repo>-wt/<name> -b <branch-name>
```

If the branch already exists on origin:
```bash
git -C <repo> worktree add ../<repo>-wt/<name> <existing-branch>
```

### List worktrees

```bash
git -C <repo> worktree list
```

### Remove a worktree

```bash
git -C <repo> worktree remove ../<repo>-wt/<name>
```

If the worktree has uncommitted changes, git will refuse. Either commit,
stash, or `--force` with intent.

### Prune stale entries

```bash
git -C <repo> worktree prune
```

Run this if you deleted a worktree directory manually instead of via
`worktree remove`.

## Setup checklist for a new worktree

After `worktree add`:

1. **Install dependencies.** If the project has a setup script, run it in
   the new tree. Node_modules, venvs, and build artifacts are NOT shared
   across worktrees.
2. **Verify a clean baseline.** Run the project's smoke test or `pytest`
   once. If it fails in the worktree but passes in main, investigate
   before adding new changes — worktree-specific env/path issues mask
   real bugs later.
3. **Point the subagent/worker/IDE at the worktree path,** not the main
   tree. If spawning a Quartermaster worker, set its working directory to
   the worktree.

## Interaction with Conductor workspaces

Conductor (per memory) creates workspace handoffs between branches.
Worktrees are a lower-level primitive that Conductor can use under the
hood. When using Conductor directly, let it manage worktrees. When
spawning a subagent without Conductor, create the worktree manually.

## Interaction with other skills

- **`/work-order`** — if the work order is non-trivial and the recipient is
  a subagent or worker, include the worktree path in the Context section
  so the recipient works in the right tree.
- **`/checkpoint`** — checkpoints are worktree-scoped. Run `/checkpoint` in
  the worktree before a break; it captures that tree's state.
- **`/state-doc`** — each worktree can have its own `STATE.md`. Do not
  share `STATE.md` across worktrees unless the work is tightly coupled.
- **`/ship`**, **`/land-and-deploy`** — run these from the worktree of the
  branch being shipped, not from main.
- **`/finishing-a-development-branch`** (if you add that skill later) —
  natural cleanup step that removes the worktree after merge.

## Completion / cleanup

When the work on a worktree is merged or abandoned:

```bash
git -C <repo> worktree remove ../<repo>-wt/<name>
```

If the branch is merged to main, delete it:
```bash
git -C <repo> branch -d <branch-name>
```

Stale worktrees waste disk (node_modules, venvs) and confuse future
searches. Clean them up the same day the work lands.

## Anti-patterns

- **Nesting worktrees inside the main tree** — breaks `rg`, IDE indexers,
  `find` commands; makes it easy to accidentally edit the wrong tree
- **Sharing a venv across worktrees via symlink** — masks Python version
  and dependency differences between branches; recreate the venv per tree
- **Long-lived worktrees for "maybe I'll come back to this"** — stale
  worktrees accumulate. Remove them when the work is paused >1 week;
  recreate cheaply if you resume.
- **Running `git worktree add` without `-b`** — this creates a worktree on
  the current branch, which is almost never what you want. Always name
  the branch explicitly.
- **Running `/ship` from the main tree when the branch is in a worktree** —
  `/ship` uses the current working directory to infer the branch. Run it
  from the worktree.

## Attribution

Pattern adapted from `obra/superpowers` `using-git-worktrees` skill (MIT).
Conductor-specific integration notes are jjstack additions.
