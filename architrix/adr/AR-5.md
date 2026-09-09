---
id: AR-5
title: A jjstack skill may shadow a Claude Code built-in only when the built-in keeps another name, and the shadow is declared
status: accepted
spec_refs: []
paths: ["bin/jjstack-verify-skills", "bin/jjstack-builtins-refresh", "bin/jjstack-prune-stale-links", "references/claude-code-builtins.txt", "skills/review/SKILL.md", "skills/jj-security-review/SKILL.md", "setup", ".github/workflows/verify.yml", "test/smoke.sh"]
supersedes: null
superseded_by: null
created: 2026-09-09T19:35:00+00:00
updated: 2026-09-09T19:35:00+00:00
---

# AR-5: A jjstack skill may shadow a Claude Code built-in only when the built-in keeps another name, and the shadow is declared

## Context

The wrapper pattern deliberately shadows gstack skill names so a user keeps typing the command they already know. That contract was written when gstack was the only other thing in the namespace.

Claude Code has since shipped built-in commands of its own, on a cadence jjstack does not control. Two of them collide with jjstack skills today, verified against the registrations inside the installed binary of Claude Code 2.1.266:

- `/review` is an alias on the `code-review` command (`{name: <code-review>, aliases:["review"]}`), added in v2.1.223. Typing `/review` reaches jjstack's; Claude's own reviewer is still reachable as `/code-review`.
- `/security-review` is a command registered by string name, with no `aliases` field at all (`{name:"security-review", description:"Complete a security review of the pending changes on the current branch", progressMessage:"analyzing code changes for security risks", ...}`). jjstack's `skills/security-review` took that name, and because the built-in has no second name, Claude Code's own security reviewer was unreachable by any name on an installed machine.

PR #12 proposed the first response to this: a note in the `/review` description plus a warn-only check carrying a hand-written list of built-in names. Reviewing it found three defects, each a different way of not actually holding the line. The list omitted `security-review`, so the check certified the tree clean of a collision that existed at the time it was written — and the repo's own `skills/security-review/SKILL.md` already documented that built-in in its description. Nothing in the repository invoked the check: `grep -rn 'verify-skills'` returned the script and one ADR, the only workflow was a post-merge version bump on `main`, and there was no CI on pull requests at all — so the PR's stated rationale, "warns and never fails so CI stays green", described a CI that did not exist. And nothing tested it: deleting the whole check changed no observable outcome.

A fourth constraint emerged from measuring the proposed fix rather than reading it. The harness truncates a skill description near 1535 characters. PR #12 appended its note to the end of a description that then measured 1622, and the cut landed inside the note, removing the clause naming `/code-review` — the only part that told a user where the built-in went. A fix delivered as description prose is only delivered as far as the cut.

PR #12 was not landed. It was also two rewrites of `main` stale by then.

## Decision

Make the ownership boundary a rule, a declaration the check can verify, and something that runs. Documentation falls out of the declaration rather than standing in for it.

**The rule** (README, "Whose name is it"). jjstack shadows gstack names by design. It shadows a Claude Code built-in only when the built-in stays reachable under another name AND the skill declares the shadow in frontmatter. Otherwise the skill takes a `jj-` prefix.

Applied: `/review` keeps its name and declares `shadows: - "claude-code:/review -> /code-review"`, with the note naming `/code-review` moved into the first sentences of the description where the harness keeps it. `skills/security-review` becomes `skills/jj-security-review`, because its built-in has no other name and no note can route a user to a command that does not exist.

**The check** (`bin/jjstack-verify-skills`, checks 5 to 7). Check 5 fails on an undeclared collision; on a declaration with no built-in behind it, which means the built-in was renamed or removed and the description note is now lying; on an alt name that is not itself a listed built-in; on an alt that jjstack also shadows; and on a description that does not name the alt within the prefix the harness keeps. Check 6 caps every description at 1400 characters, reading both YAML block styles. Check 7 warns when the installed `claude --version` is newer than the list.

**The list is data, not a comment.** `references/claude-code-builtins.txt` carries the Claude Code version it was derived from in its header, and `bin/jjstack-builtins-refresh` regenerates it from the installed binary by the two registration shapes above, printing to stdout so the maintainer diffs rather than trusts. PR #12's list was hand-written with a prose comment saying to re-check it on a minor bump; it was already wrong on the day it was written, which is the argument against that form.

**It runs.** `.github/workflows/verify.yml` runs `jjstack-verify-skills` and `test/smoke.sh` on every pull request. This is the load-bearing piece: without it the rule and the check are prose too, and the next collision lands exactly as silently as this one did.

**Renames clean up after themselves.** `bin/jjstack-prune-stale-links` removes an installed link whose target resolves inside this repository's `skills/` and no longer carries a `SKILL.md`, restoring a gstack original when the manifest names one. It is driven by the skills directory rather than the install manifest, and it is a separate script rather than a loop inside `setup` so the suite can exercise it against a fixture instead of an installer that mutates a real skills directory.

Delivered as PR #35, merged at `b8b8de0`.

## Consequences

Accepted. `/security-review` changes name for every existing user. Re-running `./setup` removes the orphaned link, and the CHANGELOG says so; anyone who does not re-run keeps a link pointing at a directory that no longer exists and a skill the harness lists but cannot load. This was verified live rather than asserted: on the development machine the link existed and dangled after the pull, and `./setup` removed it.

Accepted. The built-in list is derived from a minified binary by matching two registration shapes. That is checkable today and brittle across a Claude Code restructure. Check 7's version warning is the mitigation: the list announces the version it describes and says when it is behind, so a shape change surfaces as a stale list rather than as a silently wrong answer. The alternative considered and rejected was keeping the list by hand, which is exactly how PR #12's went wrong.

Accepted. The 1400-character ceiling is 40 characters below the tallest real description (`save-and-clear`, 1360). A skill author who wants a longer description has to shorten it or move the ceiling deliberately, which is the intended friction, but it will be hit.

Gained. The failure this class produces — a user reaching the wrong tool under a name they trust — now fails a check rather than waiting to be noticed. Both live collisions are covered: one declared and documented, one renamed away.

Gained. jjstack has pull-request CI for the first time. Every check in the tree, not only these, now runs before a merge rather than after.

Learned, and worth recording because it recurred inside its own fix. Three guards written for this change were satisfied by a comment rather than by the behaviour they named, and two assertions could not fail at all — one testing existence on a symlink that is dangling by construction, so it read the same before and after the operation. None of that was visible by reading; all of it surfaced by mutating the fixes and watching which assertions stayed green. Twelve mutants across three rounds, all killed in the final run, with the harness refusing to report a mutation whose target string was absent — a mutant that changes nothing is neither a kill nor a survivor.

Outstanding, other owners. `test/settings-lint.sh`, `test/permission-policy-check.py` and `test/permission-floor-mutation.py` arrived with AR-4 and are invoked by nothing; `verify.yml` runs only the skill checks and the smoke suite. That is this ADR's own defect class pointing at AR-4's gate, and it belongs to whoever owns that change. Separately, the Architrix MCP could not see AR-3 or AR-4 when this record was written and would have assigned AR-3 to it, overwriting an accepted decision, so this file was written directly.
