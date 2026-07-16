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
  and force-stops itself via `tm_stop`, which kills the Claude child AND its
  manager so the worker is completely gone. Otherwise it ends the reply with
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

## 5b. Tubemail-driven close — settle the ledger, then force-stop

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

### 2. Force-stop yourself via the manager

```
mcp__tubemail__tm_stop(worker="<name>")
```

Three things to get right:

- **Pass the BARE worker name, not `<name>-manager`.** `tm_stop` routes
  the `force_stop` command to `<worker>-manager` itself — handing it
  `<name>-manager` would address `<name>-manager-manager` and hit
  nothing. (This differs from /save-and-clear's 5b, where "restart
  fresh" is not a slash-command and you address the manager yourself.)
- **`tm_stop` is the only true terminal path.** It kills the Claude
  child, removes its PID file, unregisters from the hub, and exits the
  manager — the worker is completely gone. Do NOT instead type `/exit`
  via `tm_send`: the manager is a supervisor process and a child that
  exits under it is not documented to stay exited. Use the tool that is
  documented as terminal.
- **The call will probably never return, and that is success.** The
  manager kills you as it processes the command, so expect no result.
  Do not retry it, and do not report a missing result as a failure.

**Ordering is load-bearing: print your text BEFORE the tool call.**
Unlike the restart path, `force_stop` does not wait for an idle prompt —
it kills immediately. So emit the step 5 report and the closing line as
assistant text first, and make `tm_stop` the LAST tool call of that same
message. Text already streamed is persisted to the transcript; anything
you planned to say *after* the call is never written.

The last visible text before the `tm_stop` call must be exactly this
single line:

```
All pertinent information saved — exit signal sent via tubemail manager.
```

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
| 5b signal | `tm_send(<name>-manager, "restart fresh")` | `tm_stop(<name>)` |
| After 5b | fresh context, same worker, `/resume-from-clear` | worker and manager gone |
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
