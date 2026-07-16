---
name: save-and-exit
description: >
  Extract durable lessons from the current conversation into project auto-memory
  before the session ENDS for good, then shut the session down. Same sweep as
  /save-and-clear — filters surprises and decisions worth keeping from ephemera
  worth dropping (code, git history, debugging recipes), writes one memory file
  per durable lesson with proper frontmatter, updates MEMORY.md, reports what was
  saved versus deliberately skipped — but a terminal close instead of a restart:
  if the session is a tubemail worker (detected by `$TM_WORKER_NAME` being set)
  the skill settles its QM ledger (no resume order is filed — nothing resumes)
  and asks the tubemail manager to type `/exit` into its own terminal — a clean
  shutdown through the harness's own exit path, never a process kill. Otherwise
  it ends the reply with
  "all pertinent information saved - ready to exit" so the user types `/exit`
  themselves. Use whenever the user says "save and exit", "save before exit",
  "save pertinent info then quit", "shut this worker down", "wrap up and exit",
  or invokes /save-and-exit directly. Use /save-and-clear instead when the work
  CONTINUES in a fresh context — that one files a resume order and restarts.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# save-and-exit — memory sweep, then END the session

The sweep is shared; the close is what makes this skill itself. This one
assumes **the work is finished** — the session terminates and nothing
picks it back up. If the work continues in a fresh context, use
**/save-and-clear** instead: it files a QM resume order and restarts.

The memory sweep is identical precisely because the value is identical:
a lesson is just as expensive to relearn whether the session cleared or
quit.

## When to invoke

The user typically asks for this when shutting down for the day or
retiring a worker. Common phrasings:

- "save and exit"
- "save pertinent info then quit"
- "save what matters and shut down"
- "wrap up and exit"
- "shut this worker down"
- "/save-and-exit"

Invoke proactively if the user has expressed intent to exit/quit AND the
session has produced new architectural decisions, drift discoveries,
operational ceilings, prompt/code bugs, user preferences, or other lessons
that a future session would benefit from knowing without reading the whole
transcript.

**If work is still in flight, say so before exiting.** An exit with an
unfinished loop or an open work order is usually a mistake — offer
/save-and-clear (or /rollover) instead and let the user choose.

## Steps 1-5a — run the shared base

```bash
cat ~/.claude/skills/jjstack/references/memory-sweep.md
```

Follow it exactly: locate the memory dir, sweep for candidates, dedup,
write the files, update MEMORY.md, print the report, and run the 5a
tubemail probe. Then come back here for the close.

## 5b. Tubemail-driven close — settle the ledger, then clean /exit

When 5a returned `WORKER:<name>`:

### 1. Settle your QM ledger — nothing will answer for you

**Do NOT file a resume order.** There is no successor; an order addressed
to a dead worker sits pending forever and QM never dispatches it.

That cuts the other way too: after this exit, any QM item assigned to
`<name>` is unanswerable, because the worker it routes to no longer
exists. Before stopping, list your own items:

```
mcp__quartermaster__qm_queue_list(worker="<name>")
```

For each item still open, do the honest thing — never a silent close:

- **`awaiting_review` items you filed** — these are yours to close.
  `qm_queue_mark(queue_id, status="done")` if the work landed;
  `status="failed"` if it did not. Say which in the report.
- **`in_flight` / `pending` items you will never do** — do not mark them
  done. Report them to the user by id and ask whether to reassign
  (`qm_roster_add` / re-queue to another worker) or leave them for a
  relaunched worker of the same name to pick up.

If in doubt, leave the item open and NAME it in the report. A dangling
item a human can see beats a closed one that lies.

### 2. Ask the manager to type /exit — a clean shutdown

```
mcp__tubemail__tm_send(worker="<name>", message="/exit")
```

That is the whole close. Three things to get right:

- **Address the WORKER, not `<name>-manager`.** `/exit` is a built-in
  harness command, and `tm_send` routes those automatically: the manager
  types them into the session's terminal via pty. You do not address the
  manager yourself. (This is the mirror of /save-and-clear's 5b, where
  `"restart fresh"` is NOT a built-in and therefore *must* be addressed
  to `<name>-manager` explicitly. The routing rule is the same one; the
  two skills land on opposite sides of it.)
- **NEVER process-kill the session.** Do not call `tm_stop` (which
  routes `force_stop`, killing the Claude child and its manager), and do
  not reach for any other kill path. `/exit` is the harness's own exit:
  the session closes its work, the forwarder POSTs `/goodbye`, and the
  worker registers as **💤 exited cleanly** in `tm_list_workers`. A
  force-stop skips all of that and yields a 🔴 offline worker
  indistinguishable from a crash. Clean shutdown is the point of this
  skill — an exit that looks like a crash is a failed exit.
- **A typed `/exit` waits for the prompt.** The manager types it into
  the terminal, so it lands when the session is ready rather than
  interrupting mid-turn. Still send it as the LAST tool call of the
  message, after your report text — there is no reason to say anything
  after it.

The last visible text before the `tm_send` call must be exactly this
single line:

```
All pertinent information saved — /exit sent via tubemail manager.
```

**Confirming it worked (non-destructive):** a clean exit shows as
**💤 exited cleanly** in `tm_list_workers`; 🔴 offline means the session
died some other way and the close did not do its job.

If the tubemail tools are unavailable (hub down): surface that verbatim
and fall through to **5c**.

## 5c. Manual close (no tubemail, or 5b errored)

End the assistant reply with this exact single line as the FINAL visible
text — nothing after it:

```
all pertinent information saved - ready to exit
```

Do NOT add a literal `/exit` line. Outside a tubemail worker, the agent
cannot reach into its own pty; the user types `/exit` themselves. A
one-line confirmation BEFORE the closing line is fine (e.g. naming a QM
item left open, or a follow-up the user may want). Nothing after the
closing line.

## Relationship to /save-and-clear

Same base, different end. Both run
`references/memory-sweep.md` for steps 1-5a; only 5b/5c differ:

| | /save-and-clear | /save-and-exit |
|---|---|---|
| Assumption | work continues | work is finished |
| QM resume order | filed (when work continues) | never — nothing resumes |
| Other QM items | inherited by the successor | must be settled or named now |
| 5b signal | `tm_send(<name>-manager, "restart fresh")` | `tm_send(<name>, "/exit")` |
| Why that address | not a built-in → address the manager | built-in → tm_send types it into the pty |
| After 5b | fresh context, same worker, `/resume-from-clear` | 💤 exited cleanly |
| 5c line | `ready to clear` | `ready to exit` |

/rollover is the one-verb transition built on /save-and-clear; it has no
/save-and-exit counterpart, because there is nothing to roll into.

## Iteration

This skill is meant to improve. After running it, if the user pushes back
("you saved too much" / "you missed X") capture the correction as a
feedback memory in the same project — then update the rules in the base
or this SKILL.md so the next invocation does better.

Canonical paths:
- close: `/home/jesper/PycharmProjects/jjstack/skills/save-and-exit/SKILL.md`
- sweep: `/home/jesper/PycharmProjects/jjstack/references/memory-sweep.md`
  (shared with /save-and-clear — a fix here fixes both)
