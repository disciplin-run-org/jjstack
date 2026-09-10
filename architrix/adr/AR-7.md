---
id: AR-7
title: The live skill tree is a pinned worktree, never a working checkout
status: accepted
spec_refs: []
paths: ["bin/jjstack-skills-pin", "bin/jjstack-fix-symlinks", "bin/jjstack-upgrade", "setup", "test/smoke.sh", "README.md", "CHANGELOG.md"]
supersedes: null
superseded_by: null
created: 2026-09-10T05:24:48+00:00
updated: 2026-09-10T05:24:48+00:00
---

# AR-7: The live skill tree is a pinned worktree, never a working checkout

## Context

`~/.claude/skills/jjstack` is what every Claude Code session on this machine loads. `setup` created it as a symlink to the directory it was run from, which for the maintainer is a development clone. Whatever branch that clone sat on was therefore what every session executed, and a file saved mid-edit was the live skill.

Measured on 2026-09-10. While PR #39 was in flight, the symlink resolved to `/home/jesper/PycharmProjects/jjstack` checked out on `feat/independent-review-rung`, so the machine's `/review`, `/receiving-code-review` and every other jjstack skill were that unmerged branch. The branch predated two releases: #30 as `672f5da` (0.41.0) and #34 as `7efea97` (0.41.1). `bin/jjstack-pr-unread-check`, which `/receiving-code-review` names by path, did not exist on the live tree at all. A peer session working on another pull request found this and reported it rather than editing another session's working tree.

The consequence reached the review of #39 itself: the reviewer had to create a worktree by hand, pin it to the commit under review, and record in its verdict that it had done so, because otherwise nothing in the report could say which version of the reviewer produced it. A reviewer that has to distrust its own tooling by hand is a reviewer whose approvals are worth less.

This repository had already learned the rule for the other half of the install. `setup` installs hooks by copy, and says why: "They used to be symlinked into this checkout, which made the machine-wide permission policy whatever branch the checkout happened to sit on: a `git checkout` silently changed what every session on the box was allowed to do." That is the same sentence, one directory over. The reasoning was applied to hooks and never carried to skills.

## Decision

The live skill tree is a detached worktree pinned to a release ref. `bin/jjstack-skills-pin` creates it at `~/.jjstack/skills-pin`, advances it in place, and answers `--status`, `--path` and `--resolve`. `setup` points the root link and all fifty per-skill links at whatever `--resolve` returns, and `jjstack-upgrade` advances the pin to the sha it pulled.

**A worktree rather than a copy.** A copy would have solved the same problem and matched the hooks precedent exactly, and it was rejected on cost: skills are edited constantly during development, an install step between every edit and every test gets worked around, and a rule that gets worked around is worse than no rule. A worktree keeps the developer's loop intact - edit any branch, nothing goes live until you pin it - and keeps the live tree a real git tree, so `VERSION`, `git show origin/main:VERSION` and `jjstack-update-check` keep working unchanged.

**One resolver, asked by everyone who writes a link.** `--resolve` returns the pin when there is a usable one and the checkout when there is not. `setup` and `jjstack-fix-symlinks` both ask it rather than each deciding. This is load-bearing: `jjstack-fix-symlinks` runs from `jjstack-update-check`, which runs in the preamble of nearly every skill, making it the most frequently executed writer of these links on the machine. Its first version resolved the pin tool under `$JJSTACK_DIR` rather than beside itself, which meant that under any `JJSTACK_DIR` override the resolver was simply absent, the fallback fired, and the links were re-pointed at the checkout - a pin that worked everywhere except where it was being tested. The executed test found that; reading the script did not.

**Usable means it has skills.** An interrupted `worktree add` leaves a directory that is a git tree with no `skills/` in it. Served, that is an empty skill tree and every jjstack skill silently disappears, so `--resolve` requires the directory to exist, be a git tree, and hold `skills/`.

**The prune is handed every root that can back a link.** `jjstack-prune-stale-links` recognises a link by whether its target resolves inside the repo directory it is given. With the tree pinned, links resolve into the pin, so a prune handed only the checkout matches nothing and reports success having done nothing - the exact no-op the script was extracted from `setup` to prevent, one directory over. `setup` runs it for the pin and for the checkout, the second catching links left by an install from before the pin existed.

**Distinct exit codes.** 3 means there is no git clone to hang a worktree off, which is what a tarball install looks like and is supported; 4 means the ref does not exist. `setup` branches on the difference, serves the checkout directly when it must, and says so out loud both times - a silent fallback would restore exactly the coupling this removes.

## Consequences

Accepted. A change is not live until someone pins it. That is the point, and it is a step the maintainer did not previously have to take. `jjstack-upgrade` takes it automatically on the ordinary path, so the step is only manual when deliberately serving something other than the latest release.

Accepted. The pin is a second working tree of the same repository on disk, roughly the size of the repo. `git worktree list` gains an entry.

Accepted. A tarball install gets the old behaviour, because there is nothing to pin. It is warned rather than silently degraded.

Gained. What every session executes is now a decision with a timestamp rather than a side effect of `git checkout`. A reviewer can state which version of the reviewer produced a verdict without building a worktree by hand first.

Gained. `jjstack-fix-symlinks` no longer decides for itself where links point, which removes the only path that could undo the pin between sessions.

Learned, and it is the same lesson as AR-5's. Three guards written for this change were grep-text assertions about how the scripts were spelled, and one of them went red the moment the executed tests forced a call to change shape - it was tracking wording, not behaviour. It was replaced with an absence assertion about the property. Seven mutants were run across the resolver, the repairer, the upgrade, `setup` and the exit codes; all were killed, and the two that mattered most - the resolver returning the checkout, and the repairer re-pointing links at it - each failed a test that runs an actual branch edit against an actual served tree.

Outstanding. This ADR fixes the skills half. `bin/jjstack-statusline-install` and the OWASP reference cache still resolve paths from `$JJSTACK_DIR`; neither changes what a session is allowed to do or which skill it loads, so neither is in this change.
