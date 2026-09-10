---
id: AR-7
title: Continuation is an artifact only /rollover writes, not a judgement each close makes
status: accepted
spec_refs: []
paths: ["bin/jjstack-rollover-slot", "bin/jjstack-verify-skills", "hooks/shared-memory.sh", "references/memory-sweep.md", "references/qm-ledger-settle.md", "references/rollover-handover.md", "skills/rollover/SKILL.md", "skills/save-and-clear/SKILL.md", "skills/save-and-exit/SKILL.md", "skills/resume-from-clear/SKILL.md", "skills/qa-build-loop/SKILL.md", "test/smoke.sh", "README.md", "CHANGELOG.md"]
supersedes: null
superseded_by: null
created: 2026-09-09T00:00:00+00:00
updated: 2026-09-09T00:00:00+00:00
---

# AR-7: Continuation is an artifact only /rollover writes, not a judgement each close makes

## Context

Jesper reported that `/save-and-clear` and `/save-and-exit` sometimes performed a rollover: he asked to clear or to exit and woke in a fresh context that had picked the previous session's unfinished work back up.

Two conditions produced it, and neither was a bug in the sense of a wrong line of code. `/save-and-clear` step 5b read: "**If multi-turn work continues past this session** (mid-loop, open QM items you filed, an unfinished work order): file the resume order FIRST, addressed to yourself." That condition is true of almost every session that is worth sweeping memory for, so the branch fired by default rather than by exception. On the entry side, `/resume-from-clear` triggered on "waking with a fresh context and evidence of unfinished work (handover memory, pending QM self-item, qa-build-loop decisions journal without a morning report)" — so a memory sweep that merely *described* unfinished work was itself the evidence that made the next session resume it.

Underneath both sat a factoring choice. AR-1 had extracted `references/memory-sweep.md` as the shared base for the save-and-* family, which was right, but `/rollover` was then defined as "run /save-and-clear with step 5b tightened". The continuation machinery — the resume order, the injection, the restart — therefore lived inside `/save-and-clear`, and `/rollover` was a thin wrapper that made one of its optional branches mandatory. A skill cannot make a mechanism it does not own unavailable to its own base.

The three intents are genuinely distinct and a user picks between them by what happens next, not by how full the context is: end the session, start a different task, or continue this work. Two of the three ran the same machinery.

## Decision

**Continuation is an artifact, not a judgement.** `bin/jjstack-rollover-slot` owns a handover file at `~/.claude/projects/<dashified-cwd>/rollover/<worker>.md`. `/rollover` writes it; `/resume-from-clear` consumes it; nothing else touches it. Whether a session resumes is now a file that exists or does not, which is the property the prose condition never had.

**Three verbs, three closes, one shared sweep.** `/rollover` runs the base and owns its whole close. `/save-and-clear` and `/save-and-exit` run the base, settle the Quartermaster ledger through a second shared reference, and hand nothing on. `/rollover` no longer delegates to `/save-and-clear`, so neither save-and-* skill contains a mechanism that could resume work.

**The slot lives outside the auto-memory index deliberately.** A handover written into `MEMORY.md` is loaded by every later session in that project, which reintroduces the same defect through a different door: the artifact meant for one successor becomes context for all of them. Nothing indexes the rollover directory.

**The slot is keyed on the worker, not the directory.** iris-qa hosts `iris-qa-tm`, `iris-qa-coder-tm` and `iris-qa-ui-tm` in one working directory. Keying on the cwd alone would have them overwrite each other's handovers.

**`consume` renames rather than deletes.** It is what stops a second `/clear` from resuming the same work twice, and it keeps the handover readable when a resume goes wrong.

**`status` carries a seven-day window.** The prompt hook surfaces a live slot on every prompt, so a handover nobody consumed would nag indefinitely. The window governs nagging only; `consume` ignores it.

**Carriers are redundant by design, and the count differs by session type.** A plain session gets the slot, the line `/rollover` ends on, and the `UserPromptSubmit` hook. A worker gets those plus the QM resume order and the tubemail self-message. Each has failed in the field, so each is enough alone. Jesper chose this shape explicitly during planning: "hook + typed command + QM order".

**The hook check runs before the prompt-shape filters.** `shared-memory.sh` exits early on prompts under twelve characters and on system blocks. The prompt that most needs the handover notice is exactly the short one someone types before remembering `/resume-from-clear`, so a waiting slot overrides both filters and nothing else does.

## Consequences

**The split is enforced, not described.** `bin/jjstack-verify-skills` check 8 pins the continuation mechanisms to the files allowed to carry them, in three ways: a carrier outside the allowed set means the mechanism leaked; no carrier at all means the guard is watching something the repo no longer has; and carriers that exist but none in the *primary* set mean the mechanism left the skill that must have it and only prose about it remains. AR-1 claimed the anchors dependents cite "are now checked"; they were not, and this is the check that makes the claim true.

**The first version of that check did not hold the property it claimed**, and the independent review proved it by mutation in both directions rather than by reading. The markers were fixed strings, and the script's own documented calling convention walked past them: options are parsed before the verb, so `jjstack-rollover-slot --cwd DIR write` does not contain `jjstack-rollover-slot write`. A bypass planted in `/save-and-clear` left both gates green. In the other direction, deleting `/rollover`'s only slot write left the tree green too, because the contract reference names every mechanism and sat in every row's allowed set — so the "matches nothing" branch could not fire. The corroborating tell was in the output all along: the check printed the *allowed* list under the words "carried only by", and so named `hooks/shared-memory.sh` as a carrier of a string that file has never contained. Three consequences, and the third is the general one:

- The patterns are regexes tolerant of the option form, plus one row keyed on the script name alone, which catches the variable form the hook itself uses.
- Each row names a primary set, and a row whose carriers are all prose fails.
- **A guard reports what it measured, never what it permits.** Printing the allowed list makes every run look like a successful measurement. Had it printed the carriers, the leak was visible on the first run.

**A guard that reads as authoritative and is not is worse than the prose it replaced**, because the prose never claimed to be checked. That is the standard this check is now held to, and the reason its fixtures copy the real tree: the previous fixtures built a synthetic skills tree with no contract reference, so their shape differed from the real tree in exactly the way that decided the outcome.

**Markers are mechanisms, never the word "rollover".** Each of these skills legitimately names the others in its comparison table, and a grep for a name survives deleting the code that name describes. The markers are the Quartermaster call and the slot verbs.

**`status` has a wider allowed set than `write` and `consume`**, which is an asymmetry rather than an oversight. `status` only reads: it is how the hook detects a handover and how `/rollover` verifies the one it just wrote, so its verification section is runnable rather than aspirational. Handing work on is `write` and picking it up is `consume`; those stay pinned to one skill each.

**The two save-and-* closes gained a duty they did not have.** An `in_flight` item belongs to a session about to stop existing, and Quartermaster will not dispatch that worker anything else while it holds one — so an abandoned item stalls the queue silently. `references/qm-ledger-settle.md` carries the procedure for both. The previous advice to leave items "for a relaunched worker of the same name" is withdrawn: that worker, if it ever exists, has no context and no instruction to look.

**The timeline was a second route to the same defect, and closing it needed tubemail.** `/sync-inbox` is told to prefer false positives and re-do anything it cannot confirm was handled. After a `--continue` restart that is right; after a *fresh* restart the successor has no context to confirm against, so it re-executes a settled timeline — accidental continuation arriving through the transport instead of through a resume order. Filed as QM #615, and tubemail went further than the ask: the boundary is a first-class `session_boundary` event posted with a new `tm_session_boundary` tool, `tm_receive(since_boundary=True)` reads from it, and the manager now types `/sync-inbox fresh` so the skill branches on an argument rather than inferring the restart flavour. In fresh mode the doubt rule inverts — ask the orchestrator rather than re-execute — because "re-do it when unsure" replays everything when you can confirm nothing.

**That review caught a defect in this record's first draft.** The boundary marker was posted with `tm_send`, which DELIVERS to the worker's channel: the marker arrived in the very session posting it, as an inbound work order announcing that its own work was settled. `tm_session_boundary` records the event and fans out only to the UI and roster streams. The ordering matters too, and is now checked by line number rather than asserted in prose: everything at or above the newest marker is invisible to a fresh start, so `/rollover` posting its marker after its self-message would hide the message that bootstraps its own successor. All three closes mark the timeline; only `/rollover` has something below the mark that must survive.

**Quartermaster needs no change.** It detects a rollover through `has_self_addressed_open_item`, which keys on the requester rather than on the queue label, so renaming the label to "Rollover resume order" does not reach it. The context watchdog already nudges `/rollover` by name.

**The project-directory key was derived, not guessed, only after review.** The first version replaced `/` with `-` and nothing else. Measured against the 47 project directories on this machine that record a cwd, that reproduces 26; replacing every non-alphanumeric character reproduces 41, and the remaining six are stale keys from a repository rename rather than a different rule. Two live directories broke: a path containing `.` and a path containing a space both resolved to a directory with no session logs, so `transcript` returned nothing and exit 1, and the handover would have carried no transcript path — dropping the authoritative half of the handover silently, in the one field this reference insists cannot be replaced by a summary.

The rule is fixed, and more importantly it is **no longer load-bearing**. The observed data cannot fully pin it: no recorded cwd carries punctuation beyond `/`, `.`, space and `-`, so two candidate rules are indistinguishable on every sample. The slot itself does not care, because `write` and `status` derive identically and a wrong key is merely a different directory. Only `transcript` must agree with the harness, and it now asks the logs rather than trusting the rule — if the derived directory holds no session log, it finds the directory whose logs record this cwd. Deriving beats guessing; making the guess unable to matter beats both.

**A latent test defect surfaced while building the guard.** The verifier colors its `ok` label, so the literal string `ok  ` never appears in its output. Three assertions in `test/smoke.sh` anchored on it, two of them negatives that therefore could not have failed. Fixed with a plain-text view, and given a control that proves the pattern matches the specimen and misses that same line while the escapes are still in it. The lesson generalises past this file: an assertion that greps a tool's human-readable output is reading a rendering, not a value.
