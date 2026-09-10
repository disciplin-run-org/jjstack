---
id: AR-9
title: A release is a tag on the merged commit, never a commit to main
status: accepted
spec_refs: []
paths: [".github/workflows/version-bump.yml", "bin/jjstack-release-version", "bin/jjstack-version", "bin/jjstack-update-check", "bin/jjstack-upgrade", "bin/jjstack-skills-pin", "setup", "skills/jjstack-repair/SKILL.md", "test/smoke.sh"]
supersedes: null
superseded_by: null
created: 2026-09-10T12:01:46+00:00
updated: 2026-09-10T12:01:46+00:00
---

# AR-9: A release is a tag on the merged commit, never a commit to main

## Context

Rung 4 of the Definition of Done put branch protection on main: one approving
review and a passing `verify` check, no bypass list. The version-bump workflow
predated it. After every merge it committed a bumped `VERSION` as
github-actions[bot] and ran `git push origin main --tags`.

From #41 (918a291) onwards, every run failed. The job log of run 34448355753
shows GitHub refusing main with GH006, "Changes must be made through a pull
request" and "Required status check \"verify\" is expected", in the same push
that accepted `v0.42.1`. Protection is per ref, so the tag landed on a commit
that never reached main. #43's run did the same with `v0.43.0`. From then on
every run counted from `VERSION`, still 0.42.0, computed v0.43.0 again, and died
at `git tag` because it existed.

`VERSION` on main stayed at 0.42.0 through six merged pull requests. The update
check compares a tree's `VERSION` with `origin/main:VERSION`, so no install was
told there was anything to upgrade to.

The fixes that keep a version commit all weaken what rung 4 established or cost
more than the problem:

- A bypass for the bot means a token that can write to main without review or
  `verify`. That is the hole the protection closed.
- A bump pull request per merge doubles the review load for a one-line file.
- Asking authors to bump `VERSION` in their own pull requests makes every
  concurrent pull request conflict on the same line.

## Decision

A release is a `vX.Y.Z` tag on the merged commit, pushed on its own. Branch
protection does not cover tags, so nothing has to bypass anything.

- **Cutting a release.** `.github/workflows/version-bump.yml` runs
  `bin/jjstack-release-version`, tags `HEAD` with what it prints, and pushes
  only `refs/tags/<new>`. It runs one release at a time.
- **Choosing the number.** The bump type comes from commit subjects since the
  nearest release reachable from `HEAD`, as before: a breaking change is a
  major, `feat` a minor, `fix` a patch, and anything else releases nothing. The
  base is the highest version tag anywhere in the repository, so a number an
  orphan already holds is never reused.
- **Reading a version.** `bin/jjstack-version` returns the nearest version tag
  reachable from a commit. The update check, `jjstack-upgrade`,
  `jjstack-skills-pin --status`, `setup` and `/jjstack-repair` all read it
  there. It is reachable rather than highest, because an orphan is not a
  release the tree contains.
- `VERSION` is deleted, so no second number can disagree with the tag.

## Consequences

- No automation writes to main. The rung 4 floor holds with no exceptions.
- The two orphan tags need no deletion. Neither is reachable from main, so no
  reader reports one, and the next release numbers past them (v0.44.0).
- A tree with no reachable version tag has no version: a tarball install, or a
  clone that has not fetched tags. The update check stays silent for it. A
  tarball install could not reach the old remote comparison either, because it
  left the script at the local read first, so no working behaviour is lost.
- A release lands one workflow run after its merge. The update check and
  `jjstack-upgrade` fetch tags as well as the branch, so a tag cut after its
  commit was fetched is still seen.
- Releases are ranges, not one per merge. With the concurrency group, a burst
  of merges can cancel a pending run, and that commit's changes ship in the
  next tag.
- AR-7 names `VERSION` among the reasons the served tree is a worktree. The
  reasoning holds unchanged: a git tree resolves its release tags the same way
  it resolved the file. This decision does not supersede AR-7.
- `skills/github-setup` and `skills/mcp-server` still teach other repositories
  the commit-a-VERSION workflow, which breaks the same way under branch
  protection. The `mcp-server` variant also bakes `VERSION` into Docker images,
  so this decision does not transfer to it as-is. Both are left for their own
  change.
- Chosen by Jesper on 2026-09-10, from three options: let the bot bypass
  protection, bump through a pull request, or make tags the source of truth.
