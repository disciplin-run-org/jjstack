---
name: save-and-clear
description: >
  Keep this session's lessons, then start a NEW task with a clean context.
  Runs the shared memory sweep — filters surprises and decisions worth
  keeping from ephemera worth dropping (code, git history, debugging
  recipes), writes one memory file per durable lesson, updates MEMORY.md,
  reports what was saved versus deliberately skipped — then settles the
  Quartermaster ledger and closes. It hands NOTHING to the next session:
  no handover slot, no resume order, no injection message, so the fresh
  context starts on whatever you ask it next. In a tubemail worker
  (`$TM_WORKER_NAME` set) it posts a session-boundary marker and signals a
  fresh restart via the manager; otherwise it ends with "all pertinent
  information saved - ready to clear" so you type `/clear` yourself.
  Use whenever the user says "save before clear", "checkpoint memory",
  "save pertinent info", "prep for a clear", "what should we keep", or
  invokes /save-and-clear directly.
  Use /rollover instead when THIS work continues in the fresh context —
  that is the only verb that resumes. Use /save-and-exit when the session
  is ending for good.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# save-and-clear — keep the lessons, drop the thread

The sweep is shared; the close is what makes this skill itself. This one
assumes **the next thing is a different thing**. The context is wiped, the
lessons survive in memory, and the successor starts from whatever you ask
it — not from what this session was doing.

**This skill resumes nothing.** It writes no handover slot, files no QM
resume order, and posts no injection message. If you catch yourself
reaching for one, the user wanted **/rollover**.

That is not a style rule. Until 2026-09-09 step 5b filed a resume order
whenever "multi-turn work continues past this session" — which is true of
every mid-task session — so asking for a clean context produced a
successor that picked the old task straight back up. Three verbs, three
closes, and `bin/jjstack-verify-skills` check 8 fails the build if a
continuation mechanism reappears here.

## When to invoke

The user is switching tasks and wants the lessons kept:

- "save pertinent information before a /clear"
- "checkpoint memory"
- "what should we keep before I clear"
- "prep for /clear"
- "/save-and-clear"

Invoke proactively if the user has expressed intent to clear or compact
AND the session produced new architectural decisions, drift discoveries,
operational ceilings, prompt or code bugs, user preferences, or other
lessons a future session would otherwise pay for twice.

**If the work is mid-flight, say so in one line before sweeping.** An
open loop or a half-landed change usually means /rollover was the verb.
Name it and let the user choose; do not pick for them by quietly filing a
handover.

## Steps 1-5a — run the shared base

```bash
cat ~/.claude/skills/jjstack/references/memory-sweep.md
```

Follow it exactly: locate the memory dir, sweep for candidates, dedup,
write the files, update MEMORY.md, print the report, and run the 5a
tubemail probe. Then come back here for the close.

## 5b. Settle the Quartermaster ledger — both paths

```bash
cat ~/.claude/skills/jjstack/references/qm-ledger-settle.md
```

Follow it. The short version: an `in_flight` item belongs to a session
that is about to stop existing, and QM will not dispatch this worker
anything else while it holds one. Report it, correct it forward, or name
it — never close it silently, and never leave it "for a relaunched worker
of the same name".

## 5c. Tubemail close — boundary marker, then FRESH restart

When 5a returned `WORKER:<name>`:

1. **Post the session-boundary marker** on your own timeline:

   ```
   mcp__tubemail__tm_session_boundary(worker="<name>",
       reason="/save-and-clear")
   ```

   Everything above the marker is settled. The successor restarts with
   no conversation context, so it cannot tell a finished work order from
   an unanswered one; `/sync-inbox fresh` reads the marker via
   `tm_receive(since_boundary=True)` and never re-executes anything above
   it. Without it, a clear re-runs the orders the previous session
   already finished — the accidental continuation this skill exists to
   end, arriving through the timeline instead of through a resume order.

   **Use `tm_session_boundary`, never `tm_send`.** `tm_send` DELIVERS to
   the worker's channel, so a marker sent that way lands in the still-live
   session as an inbound work order telling it its own work is settled.
   The marker tool records the event and fans out only to the UI and
   roster streams. (Caught by tubemail-tm on QM #615, against the first
   draft of this step, which used `tm_send`.)

2. **Signal the fresh restart — to the MANAGER, exactly once:**

   ```
   mcp__tubemail__tm_send(worker="<name>-manager",
       message="restart fresh",
       meta={"kind": "restart", "fresh": True})
   ```

   `"restart fresh"` is not a slash-command, so `tm_send` will not
   auto-route it — you address `<name>-manager` yourself. (This is the
   mirror of /save-and-exit's close, where `/exit` IS a built-in and
   therefore goes to the bare worker name. One routing rule, two skills
   on opposite sides of it.) Send it ONCE and never also call
   `tm_restart` on yourself: the fresh flag is one-shot, and a duplicate
   makes the second restart revert to `--continue` (observed live
   2026-07-04).

Never a bare `/clear` here: it keeps the process but loses the
conversation-held identity, so QM dispatch stops matching the worker (the
2026-07-04 amnesia incident). A fresh restart rebuilds identity from the
startup `/rename`.

If the tubemail tools are unavailable (hub down): surface that verbatim
and fall through to **5d**.

End the reply with this exact single line as the FINAL visible text —
nothing after it:

```
All pertinent information saved — fresh-restart signal sent via tubemail manager.
```

## 5d. Manual close (no tubemail, or 5c errored)

End the reply with this exact single line as the FINAL visible text —
nothing after it:

```
all pertinent information saved - ready to clear
```

Do NOT add a literal `/clear` line. Outside a tubemail worker the agent
cannot reach into its own pty; the user types `/clear` themselves. A
one-line note BEFORE the closing line is fine (a follow-up worth
remembering, a QM item left open). Nothing after it.

## Iteration

If the user pushes back ("you saved too much", "you missed X"), capture
the correction as a feedback memory in the same project, then fix the
rule in the base or in this file so the next invocation does better.

Canonical paths:
- close: `/home/jesper/PycharmProjects/jjstack/skills/save-and-clear/SKILL.md`
- sweep: `/home/jesper/PycharmProjects/jjstack/references/memory-sweep.md`
- ledger: `/home/jesper/PycharmProjects/jjstack/references/qm-ledger-settle.md`
  (both shared with /save-and-exit — a fix there fixes both)
