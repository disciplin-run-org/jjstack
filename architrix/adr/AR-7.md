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

**The split is enforced, not described.** `bin/jjstack-verify-skills` check 8 pins the continuation mechanisms to the files allowed to carry them. Two failure modes, and the second matters more: a marker outside its allowed set means the mechanism leaked, and a marker found *nowhere* fails too — a guard watching something the repo no longer has would pass forever without inspecting anything. AR-1 claimed the anchors dependents cite "are now checked"; they were not, and this is the check that makes the claim true.

**Markers are mechanisms, never the word "rollover".** Each of these skills legitimately names the others in its comparison table, and a grep for a name survives deleting the code that name describes. The markers are the Quartermaster call and the slot verbs.

**`status` has a wider allowed set than `write` and `consume`**, which is an asymmetry rather than an oversight. `status` only reads: it is how the hook detects a handover and how `/rollover` verifies the one it just wrote, so its verification section is runnable rather than aspirational. Handing work on is `write` and picking it up is `consume`; those stay pinned to one skill each.

**The two save-and-* closes gained a duty they did not have.** An `in_flight` item belongs to a session about to stop existing, and Quartermaster will not dispatch that worker anything else while it holds one — so an abandoned item stalls the queue silently. `references/qm-ledger-settle.md` carries the procedure for both. The previous advice to leave items "for a relaunched worker of the same name" is withdrawn: that worker, if it ever exists, has no context and no instruction to look.

**One gap is left open on purpose, and it belongs to tubemail.** `/sync-inbox` is told to prefer false positives and re-do anything it cannot confirm was handled. After a `--continue` restart that is right; after a *fresh* restart the successor has no context to confirm against, so it can re-execute a settled timeline. `/save-and-clear` now posts a `SESSION-BOUNDARY` marker before signalling the restart, which is the most jjstack can reach from its own side. Making `/sync-inbox` stop at that marker deterministically — and deciding whether it should be a first-class event kind rather than a string in a message body — is tubemail's change, filed as QM #615 rather than made here.

**Quartermaster needs no change.** It detects a rollover through `has_self_addressed_open_item`, which keys on the requester rather than on the queue label, so renaming the label to "Rollover resume order" does not reach it. The context watchdog already nudges `/rollover` by name.

**A latent test defect surfaced while building the guard.** The verifier colors its `ok` label, so the literal string `ok  ` never appears in its output. Three assertions in `test/smoke.sh` anchored on it, two of them negatives that therefore could not have failed. Fixed with a plain-text view, and given a control that proves the pattern matches the specimen and misses that same line while the escapes are still in it. The lesson generalises past this file: an assertion that greps a tool's human-readable output is reading a rendering, not a value.
