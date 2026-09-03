---
name: spawn-review
version: 0.1.0
description: |
  Start a SECOND Claude session on an isolated git worktree, so a review can run
  on another branch or PR while you keep coding on yours. One repo directory can
  only be on one branch; this creates a worktree, opens a tmux window in it, and
  launches Claude there seeded with a review prompt.
  Trigger on: "spawn a review", "review this PR in another session", "review X
  while I keep working", "open a second session for", "review a branch without
  switching", "parallel review session".
  Do NOT trigger for: reviewing the diff you are already on (use /review), a
  report-only pass in this session (use /review-stack), or when the user wants
  to switch branches themselves.
allowed-tools:
  - Bash
  - Read
---

# spawn-review

Run `~/.claude/skills/jjstack/bin/jjstack-spawn-review` with the target.

```bash
~/.claude/skills/jjstack/bin/jjstack-spawn-review "$TARGET"
```

`$TARGET` is a PR number or any ref. Add `--prompt "..."` to pass the new session a
note about what to focus on.

## What this is for

A Claude session is an OS process in a terminal. It is not created by sending a
message, and it does not wait for the current turn to finish. What actually blocks
a parallel review is narrower: **one repo directory can only have one branch
checked out.** Two sessions in the same directory fight over the working tree.

A git worktree fixes that - same repo, same history, same object store, a second
directory on a second branch. This script does the three steps people get wrong:

1. resolves a PR number to a real ref (`pull/N/head`), or detaches a branch that is
   already checked out in the main worktree, which is the error everyone hits first:
   `fatal: 'x' is already used by worktree at ...`
2. opens a tmux window in it and launches Claude seeded with `/review-stack <target>`
3. registers the worktree so `--cleanup` can remove all of them later

## After it runs

The new session appears in `ListAgents` by name. Use `SendMessage` to ask it for
findings instead of copy-pasting between panes.

## Cleaning up

```bash
~/.claude/skills/jjstack/bin/jjstack-spawn-review --list      # what is spawned
~/.claude/skills/jjstack/bin/jjstack-spawn-review --cleanup   # remove them all
```

Worktrees are created under `.jjstack-worktrees/` in the repo and added to
`.git/info/exclude`, so they never appear in `git status` and never touch a tracked
`.gitignore`. Stale worktrees are the main way this pattern goes wrong - run
`--cleanup` when the review is done.

## Degrading

Without `tmux` on PATH the script prints the two commands to run instead of guessing
at the terminal setup. Without `gh` a PR number cannot be resolved; pass a ref
instead. Neither case leaves a half-made worktree behind.

## Do not

- Do not run two Claude sessions in the same directory. That is the thing this
  exists to avoid.
- Do not create a worktree for a review that is report-only and fits in this
  session - `/review-stack <PR#>` already makes its own throwaway worktree and
  tears it down. Reach for spawn-review when you want a *separate, persistent
  session* you can talk to.
