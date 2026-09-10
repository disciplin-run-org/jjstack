---
name: save-and-exit
description: >
  Keep this session's lessons, then END the session. Runs the same shared
  memory sweep as /save-and-clear — filters surprises and decisions worth
  keeping from ephemera worth dropping (code, git history, debugging
  recipes), writes one memory file per durable lesson, updates MEMORY.md,
  reports what was saved versus deliberately skipped — then settles the
  Quartermaster ledger and closes terminally. It hands NOTHING on: no
  handover slot, no resume order, nothing resumes. In a tubemail worker
  (`$TM_WORKER_NAME` set) it asks the manager to type `/exit` into its own
  terminal, a clean shutdown through the harness's own exit path and never
  a process kill; otherwise it ends with "all pertinent information saved
  - ready to exit" so you type `/exit` yourself.
  Use whenever the user says "save and exit", "save before exit", "save
  pertinent info then quit", "shut this worker down", "wrap up and exit",
  or invokes /save-and-exit directly.
  Use /save-and-clear when the session continues on a NEW task, and
  /rollover when THIS work continues in a fresh context.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# save-and-exit — keep the lessons, END the session

The sweep is shared; the close is what makes this skill itself. This one
assumes **the work is finished**: the session terminates and nothing picks
it back up. The memory sweep is identical to /save-and-clear's precisely
because the value is identical — a lesson costs the same to relearn
whether the session cleared or quit.

**This skill resumes nothing**, and here that is structural rather than a
choice: there is no successor. No handover slot, no QM resume order, no
injection message. `bin/jjstack-verify-skills` check 8 fails the build if
one appears.

## When to invoke

Shutting down for the day, or retiring a worker:

- "save and exit"
- "save pertinent info then quit"
- "save what matters and shut down"
- "wrap up and exit"
- "shut this worker down"
- "/save-and-exit"

Invoke proactively if the user has expressed intent to exit or quit AND
the session produced lessons a future session would otherwise pay for
twice.

**If work is still in flight, say so in one line before exiting.** An exit
over an unfinished loop or an open work order is usually a mistake. Name
the two other verbs — /save-and-clear for a new task, /rollover to carry
this work into a fresh context — and let the user pick. Do not pick for
them, and do not soften the exit by leaving a handover behind: that is the
defect this split removed.

## Steps 1-5a — run the shared base

```bash
cat ~/.claude/skills/jjstack/references/memory-sweep.md
```

Follow it exactly: locate the memory dir, sweep for candidates, dedup,
write the files, update MEMORY.md, print the report, and run the 5a
tubemail probe. Then come back here for the close.

## 5b. Settle the Quartermaster ledger

```bash
cat ~/.claude/skills/jjstack/references/qm-ledger-settle.md
```

Follow it. After this exit every item addressed to `<name>` is
unanswerable, because the worker it routes to no longer exists — so the
"never leave it for a relaunched worker of the same name" rule bites
hardest here. Report, correct forward, or name each open item.

## 5c. Tubemail close — ask the manager to type /exit

When 5a returned `WORKER:<name>`:

First, mark the timeline settled:

```
mcp__tubemail__tm_session_boundary(worker="<name>", reason="/save-and-exit")
```

Nothing resumes from this session, but the timeline outlives it. A worker
relaunched under the same name later runs `/sync-inbox` against everything
still on it and, with no context to check against, can re-execute orders
this session already answered. The marker is the fact that stops it. Use
`tm_session_boundary`, never `tm_send`: `tm_send` delivers to the worker's
channel, so the marker would arrive in this session as a work order.

Then ask the manager to type the exit:

```
mcp__tubemail__tm_send(worker="<name>", message="/exit")
```

That is the close. Three things to get right:

- **Address the WORKER, not `<name>-manager`.** `/exit` is a built-in
  harness command and `tm_send` routes built-ins automatically: the
  manager types them into the session's terminal via pty. (This is the
  mirror of /save-and-clear's close, where `"restart fresh"` is NOT a
  built-in and therefore must be addressed to the manager explicitly. One
  routing rule; the two skills sit on opposite sides of it.)
- **NEVER process-kill the session.** Do not call `tm_stop` (it routes
  `force_stop`, killing the Claude child and its manager) and do not
  reach for any other kill path. `/exit` is the harness's own exit: the
  session closes its work, the forwarder POSTs `/goodbye`, and the worker
  registers as **💤 exited cleanly** in `tm_list_workers`. A force-stop
  skips all of that and yields a 🔴 offline worker indistinguishable from
  a crash. An exit that looks like a crash is a failed exit.
- **A typed `/exit` waits for the prompt**, so it lands when the session
  is ready rather than interrupting mid-turn. Still send it as the LAST
  tool call of the message, after your report text.

The last visible text before that `tm_send` must be exactly this single
line:

```
All pertinent information saved — /exit sent via tubemail manager.
```

**Confirming it worked (non-destructive):** a clean exit shows as **💤
exited cleanly** in `tm_list_workers`; 🔴 offline means the session died
some other way and the close did not do its job.

If the tubemail tools are unavailable (hub down): surface that verbatim
and fall through to **5d**.

## 5d. Manual close (no tubemail, or 5c errored)

End the reply with this exact single line as the FINAL visible text —
nothing after it:

```
all pertinent information saved - ready to exit
```

Do NOT add a literal `/exit` line. Outside a tubemail worker the agent
cannot reach into its own pty; the user types `/exit` themselves. A
one-line note BEFORE the closing line is fine (naming a QM item left
open, or a follow-up the user may want). Nothing after it.

## The three closes, side by side

Same sweep (`references/memory-sweep.md`, steps 1-5a); only the close
differs.

| | /save-and-exit | /save-and-clear | /rollover |
|---|---|---|---|
| Assumption | work is finished | next task is a different task | this work continues |
| Handover slot | never | never | written (the only writer) |
| QM resume order | never | never | filed to itself |
| Other QM items | settled or named now | settled or named now | inherited by the successor |
| Timeline marker | `tm_session_boundary` | `tm_session_boundary` | `tm_session_boundary`, before the injection |
| Worker signal | `tm_send(<name>, "/exit")` | `tm_send(<name>-manager, "restart fresh")` | same fresh restart, after the handover |
| Why that address | built-in → tm_send types it into the pty | not a built-in → address the manager | same as /save-and-clear |
| After the close | 💤 exited cleanly | fresh context, new task | fresh context, `/resume-from-clear` |
| Plain-session line | `ready to exit` | `ready to clear` | `type /clear, then /resume-from-clear` |

## Iteration

If the user pushes back ("you saved too much", "you missed X"), capture
the correction as a feedback memory in the same project, then fix the
rule in the base or in this file.

Canonical paths:
- close: `/home/jesper/PycharmProjects/jjstack/skills/save-and-exit/SKILL.md`
- sweep: `/home/jesper/PycharmProjects/jjstack/references/memory-sweep.md`
- ledger: `/home/jesper/PycharmProjects/jjstack/references/qm-ledger-settle.md`
  (both shared with /save-and-clear — a fix there fixes both)
