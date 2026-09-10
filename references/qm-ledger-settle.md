# qm-ledger-settle — closing your Quartermaster items at a session boundary

Loaded by **/save-and-clear** and **/save-and-exit**. Both end a session's
work, so both leave the same debris behind: queue items addressed to this
worker that no successor has been told to finish.

/rollover does NOT load this file. A rollover hands the whole ledger to a
successor that is about to read it, so settling would be wrong there —
the successor inherits the items on purpose.

## Why an unsettled ledger is a real cost, not bookkeeping

An `in_flight` item belongs to a session that no longer exists. QM's
dispatch loop will not send that worker anything else while it holds one,
so a single abandoned item stops the worker's queue indefinitely. A
`pending` item nobody will do looks, on the board, exactly like work that
is about to happen. Both mislead the human reading the queue, which is the
one surface that is supposed to say what is actually in progress.

The two closes differ only in what the worker becomes afterwards:

| | after /save-and-clear | after /save-and-exit |
|---|---|---|
| The worker | a fresh context under the same name | gone |
| It will accept new dispatch | yes | no |
| An item left open is | picked up by a session with no idea why | never answered at all |

Neither is a reason to leave one open silently.

## The procedure

### 1. List what is yours

```
mcp__quartermaster__qm_queue_list(worker="<name>")
```

Also look for `awaiting_review` items YOU filed on other workers — the
requester closes those, and after this boundary nobody will.

### 2. Settle each open item honestly

- **`awaiting_review` items you filed** — yours to close.
  `qm_queue_mark(queue_id, status="done")` if the work landed,
  `status="failed"` if it did not. Verify the evidence first; never close
  on the notice alone.
- **`in_flight` items** — report before closing. `qm_queue_report` with
  what actually got done, then `qm_queue_mark(queue_id,
  status="needs_correction")` naming the boundary in the follow-up
  ("abandoned by /save-and-clear at 62% context; the next session starts
  from the report"). The follow-up item is how the work survives without
  pretending this session finished it.
- **`pending` items you will never do** — do not mark them done. Name
  them by id in your report and say who should have them. Leaving them
  pending is fine; leaving them pending *silently* is not.

### 3. Never do these

- **Never silent-close.** A `done` on work that did not happen is worse
  than a dangling item, because the board stops showing anyone the gap.
- **Never leave an item "for a relaunched worker of the same name".**
  That worker, if it ever exists, has no context and no instruction to
  look. If work must survive, it needs a follow-up item that says so.
- **Never file a resume order here.** A resume order addressed to
  yourself is the /rollover mechanism; filing one from a clear or an exit
  is the defect that made a clear behave like a rollover. If the work
  genuinely continues in a fresh context, the right verb was /rollover.

### 4. Say what you settled

The close report names every id you touched and every id you left open:

```
QM ledger: #NNN closed done (evidence: <what>), #NNN reported and
corrected forward as #NNN, #NNN left pending — needs <owner>.
```

If in doubt, leave the item open and NAME it. A dangling item a human can
see beats a closed one that lies.
