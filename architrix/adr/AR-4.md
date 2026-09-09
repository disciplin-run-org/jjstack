---
id: AR-4
title: Permission gate: a deterministic deny floor under bypass mode, with no model in the hot path
status: accepted
spec_refs: []
paths: ["hooks/permission-floor.py", "hooks/permissions.policy.json", "hooks/auto-approve-safe.sh", "setup", "uninstall", "test/permission-policy-check.py", "test/permission-floor-mutation.py", "test/settings-lint.sh", "test/fixtures/permission-policy.tsv", "bin/jjstack-permission-audit", "references/hard-gate-convention.md"]
supersedes: null
superseded_by: null
created: 2026-09-09T18:02:46+00:00
updated: 2026-09-09T18:02:51+00:00
---

# AR-4: Permission gate: a deterministic deny floor under bypass mode, with no model in the hot path

## Context

Sessions on the development machine stopped for a human permission prompt constantly, including sessions deliberately launched with --dangerously-skip-permissions, and the effect was worst during long autonomous runs such as /review and /qa-build-loop.

A 48-hour audit (2026-09-07 19:00 to 2026-09-09 08:40 PDT) over the hook log, the tubemail hub worker timelines, Quartermaster's queue.db and 150 session transcripts found: 393 permission requests forwarded to the hub with 391 distinct command strings; 430 prompts that reached a person, about 8.96 per hour; and zero deliberate rejections. Two Bash rejections in the window were mis-keys and the plan-mode rejections were edits, so the human approval rate on real prompts was 100%.

Two causes, neither in the gate's own policy.

First, the settings layer. ~/.claude/settings.json listed Bash(rm *), Bash(rm -rf *), Bash(curl *), Bash(wget *), Bash(sudo *), Bash(git push *), Bash(git reset --hard *), Bash(git clean *), Bash(chmod -R *), Bash(chown *) and nine more under permissions.ask. Per the Claude Code documentation, ask rules are evaluated before allow rules regardless of specificity, they prompt in every permission mode including bypassPermissions, and allow rules have no effect at all in bypassPermissions. That list is the verb table of an autonomous run, which is why the bypass flag appeared not to work. The accompanying 462-entry allow list was inert for a second reason as well: 391 of the 393 prompted commands began with a variable assignment, a cd, or set -a, so the prefix matcher never reached the verb.

Second, the gate itself asked Claude Haiku to rate every Bash command and deferred on any answer that was not exactly LOW, which surfaces the normal permission dialog. 176 of the prompts in the window were that path returning nothing usable. The cause was reproduced by replaying real prompted commands: commit 5559659 had tightened the answer parser to accept only a bare LOW/MEDIUM/HIGH, correcting a genuine fail-open where "Not LOW - HIGH" was read as LOW, but on long commands Haiku answers "LOW\n\n**Rationale:**..." and truncates at max_tokens: 10, so the parser saw LOW**RATIONALE:**1 and returned unrated. It was not credits, rate limits (40 of 40 parallel calls returned 200 against a 5,000 requests/minute limit) or timeouts (sub-1.5-second latency); the last genuine MEDIUM or HIGH rating in the log predates that commit.

Two open pull requests, #25 and #31, collapsed into #33, all proposed further changes to the rater. None addressed either cause.

A third fact shaped the design. 48.1% of Bash calls were compound (VAR=...; cmd, cd X && cmd, multi-line scripts), despite one-command-per-call being a standing instruction in CLAUDE.md for months. A compound command is opaque to every prefix rule the permission system has and makes the audit log unreadable, so prose alone had not carried the rule.

## Decision

Remove human judgement from the routine path entirely and make the floor deterministic, in three layers that each work in bypassPermissions mode.

1. Mode and rules become data. hooks/permissions.policy.json is the canonical policy and setup applies it verbatim, inventing no rule of its own: defaultMode bypassPermissions, zero Bash ask rules, 20 deny rules (sudo rm/dd/mkfs, mkfs, fdisk, parted, shutdown/reboot/poweroff/halt, and Read denies for pem/key/secrets/.ssh/.aws/the API key file/.credentials.json, plus Edit denies for shell rc files), and 31 allow rules covering MCP servers, read tools, settings edits and the WebFetch domain list. The permissions block is replaced rather than merged, because a policy that accretes is how the previous one reached 462 rules that matched nothing. Settings are backed up to ~/.claude/backups first and {{HOME}} is substituted at install time. The stale autoMode environment block, which named a trusted repo nobody works in and so made every real project read as unrecognized infrastructure, is deleted.

2. hooks/permission-floor.py is a PreToolUse hook on Bash that returns permissionDecision deny with a reason naming the rule and the fix. Deny rather than ask is the load-bearing choice: deny hands Claude the reason so it reroutes inside the same turn, and it applies in bypassPermissions where allow rules do not. Ten floor rules cover unbounded reach (every spelling of a filesystem root or home directory), piping fetched code into a shell, uploading a local file, naming a well-known secret path in a network command, writing to a block device, fork bombs, power commands, destructive sudo, force-pushing the trunk and git push --mirror. An eleventh rule, SHAPE, refuses a compound command with instructions to split it: use git -C rather than cd &&, run a command directly rather than assigning its output, and write a multi-line script to the scratchpad with the Write tool. Heredoc bodies, quoted spans and redirection operators are excluded from that scan before it runs, so a commit message, a fixture file and cmd 2>&1 | tail all remain single calls. Floor is evaluated against the raw command and before SHAPE, so an unterminated quote cannot hide anything and a fork bomb is reported as FORKBOMB rather than as a stray semicolon. The hook makes no network call, reads no credential, and exits 0 on any internal error so a bug in it can never block work.

3. hooks/auto-approve-safe.sh keeps only the audit line and the tubemail socket pairing that lets an orchestrator answer residual prompts remotely. It has no allow branch at all, deliberately: a hook that can approve is a hook that can become a bypass.

Hooks are installed by copy with the installed copy compared against the checkout, never by symlink.

Evidence required before this lands: 69 fixtures in test/fixtures/permission-policy.tsv, each asserting the rule rather than only the verdict, with the runner deriving the rule set from the hook itself and exiting 2 (louder than a mismatch) when the table cannot fail; test/permission-floor-mutation.py removing each rule in turn and requiring the rows that redden to be exactly the rows naming it; test/settings-lint.sh asserting the live settings file and ending with a shipped literal fired through the installed copy, driven seven ways by the smoke suite and required to fail each time; bin/jjstack-permission-audit as the standing measurement.

Delivered as PR #36. PR #33 and the branches fix/permission-gate-combined and fix/permission-hook-tm-dispatch are closed without merging.

## Consequences

Accepted. Running every terminal session in bypassPermissions means the settings layer no longer prompts for anything, so the deny rules and the PreToolUse floor are the only automated protection left. That is a deliberate trade: the prompts being removed caught nothing in 48 hours, and the floor they sit on had always been the thing actually refusing dangerous commands. The residual set no mode auto-approves still reaches a person: critical-path rm targeting a root, AskUserQuestion, MCP tools marked requiresUserInteraction, and the cross-session messaging safeguards.

Accepted. The floor is a fixed list, so a genuinely dangerous command outside those eleven shapes now runs without comment where it might previously have been rated MEDIUM and shown to someone. The audit measured that path at 12 prompts in 48 hours, all approved.

Accepted. SHAPE changes how Claude has to work: chained commands are refused rather than tolerated. Roughly half of all Bash calls were compound, so the adaptation is real and visible in the audit's compound-call percentage. The payoff is that every later rule, log line and allowlist entry sees a literal command.

Accepted. Replacing the permissions block wholesale discards user-added allow entries. Mitigated by a timestamped backup before every setup run, and by uninstall deliberately not reverting the block: guessing which rules the user added since would either strip protection or restore rules they never asked for.

Gained. The gate no longer depends on network reachability, an API key, rate limits or a model's willingness to answer in one word. Four failure modes that all resolved to interrupting a person are gone, and the gate is now fast enough to run on every call without a round trip.

Gained. Policy is one readable, diffable file, and settings-lint can assert that the machine matches it. The previous arrangement had no way to state what the machine was supposed to enforce, let alone check it.

Closed. Installing by copy ends the condition where the machine-wide permission policy was whatever branch a working checkout happened to sit on, so git checkout silently changed what every session could do.

Outstanding, other owners. Quartermaster escalated 35,705 of 35,709 permission rows in the window with reason "Bash call had no command string" because the hub sends it an empty input payload, appending roughly 90 rows per request into a 216 MB queue.db. The tubemail forwarder still runs a second Haiku rater of its own, now redundant. disciplin-run/.claude/settings.json still carries a Bash(sudo *) ask rule that will prompt under bypass.
