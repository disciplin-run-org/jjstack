---
name: reconnect-mcp
description: >
  Reconnect a failed MCP server using the deterministic *_reconnect_mcp path.
  Two flows: (a) a worker reconnecting its OWN failed MCP server via
  tm_reconnect_mcp on tubemail (works as long as tubemail is still up), and
  (b) the orchestrator reconnecting another worker's MCP server via
  qm_reconnect_mcp on quartermaster. Use when an MCP server shows ✘ failed
  in any /mcp dialog. Never drive /mcp manually with screenshot+keystroke
  chains — they're slow, fragile, and can trigger the "Remote Control view"
  Enter-shortcut. Trigger on: "reconnect mcp", "mcp server failed", "leanspecs
  mcp disconnected", "fix mcp connection", "my mcp died", "my own mcp dropped",
  "mcp dialog driving".
allowed-tools:
  - Bash
---

# reconnect-mcp

One tool per direction. Never manual.

## Decision: which tool

| Situation | Tool | Why |
|---|---|---|
| **You are a tubemail worker** (e.g. `leanspecs-ui-tm`, `iris-qa-tm`) and one of YOUR OWN MCP servers shows ✘ failed | `mcp__tubemail__tm_reconnect_mcp(worker=<your-name>, server=<failed>)` | tubemail is the only connection guaranteed to still work; your own manager drives YOUR /mcp dialog |
| **You are the orchestrator** (claude-qm / quartermaster session) and another worker's MCP server failed | `mcp__quartermaster__qm_reconnect_mcp(worker=<their-name>, server=<failed>)` | quartermaster is upstream of every worker's manager and has direct dispatch |
| Tubemail itself is down on a worker | Wait for tubemail to come back, OR use `qm_reconnect_mcp` from the orchestrator | tm_* tools require tubemail; if tubemail is gone the worker can't self-rescue |
| Quartermaster itself is down | Rebuild/restart the quartermaster container | qm_* tools won't reach a dead server |

Both tools accept the same `(worker, server)` shape and return the same
`{ok, server, detail}` payload. Both drive /mcp deterministically:
open dialog → navigate to the named server → select Reconnect, ~25s budget.

## Worker self-reconnect (the common case for `*-tm` workers)

You are running as `$TM_WORKER_NAME` (e.g. `leanspecs-ui-tm`). Mid-session a
system-reminder announces that some `mcp__leanspecs__*` or
`mcp__quartermaster__*` tools are no longer available — those servers
disconnected. Tubemail is still up (you can call tm_* tools).

```
mcp__tubemail__tm_reconnect_mcp(
  worker=os.environ["TM_WORKER_NAME"],
  server="leanspecs",   # or "quartermaster", whichever failed
)
```

Repeat per failed server. After each call, verify by re-running ToolSearch
on a representative tool name (e.g. `mcp__leanspecs__settings_read`).

You do NOT need to ask the user to run `/mcp` interactively. You do NOT
need to send `tm_send(message="/mcp")` and drive the dialog yourself.
`tm_reconnect_mcp` is the fast path.

## When to use

- Mid-session system-reminder announces N deferred tools no longer available
  for a named MCP server.
- The tool surface shrank and a representative tool's `ToolSearch` returns
  no match.
- A worker (via tubemail reply) reports its tool list went dark.
- `tm_list_workers` shows a worker's MCP server as failed.

## When NOT to use

- The MCP **hub** itself (the named server's container) is down — this tool
  reconnects the client, not the server. Restart the container first, then
  reconnect.
- The worker process itself is stopped (`tm_list_workers` shows offline).
  Start the worker first.
- The failure root cause is upstream (target server is down on its port,
  OAuth handshake broken, `.mcp.json` doesn't list the server). Fix the
  cause; reconnection will just fail again.
- Tubemail itself disconnected on the worker AND you are the worker. You
  can't self-rescue without tubemail. Ask the orchestrator (or a human at
  the worker's terminal) to drive `/mcp` once.

## Anti-patterns (stop doing these)

- ❌ `tm_screenshot` + `tm_keystroke` + sleeps + more screenshots. The
  deterministic Python path in the manager handles cursor-finding, screen
  polling, and timing. Use `tm_reconnect_mcp`.
- ❌ `tm_send(worker=self, message="/mcp")` — types `/mcp` but leaves the
  cursor where it was and doesn't navigate. The cleanup dance (escape
  Remote Control, re-open, navigate) is exactly what `tm_reconnect_mcp`
  exists to do for you.
- ❌ Asking the user to run `/mcp` themselves when the tool exists. Wastes
  their attention; auto mode means use the tool.
- ❌ Using raw `enter` as a keystroke when the status bar shows "Enter to
  view" — opens the Remote Control panel instead of submitting. The
  reconnect flow skips this trap.

## Return shape

```
{
  "ok": true,
  "server": "leanspecs",
  "detail": "reconnected"
}
```

or on failure:

```
{
  "ok": false,
  "server": "leanspecs",
  "detail": "server not found in dialog; listed: [google-workspace, iris-qa, ...]"
}
```

If the result's `detail` mentions `server not found` or an OAuth/Auth error,
the fix is upstream — the server isn't in the worker's `.mcp.json` at all,
or its OAuth handshake is broken. Route those to the owning code worker,
not to this flow.

## History

This skill exists because 2026-04-22 had a ~5-minute manual reconnect
session (ollama-submodule-debug aftermath). The fragile parts:
- The `❯` cursor position wasn't rendered in screenshots as expected.
- `Enter` triggered Remote Control view instead of dialog submit.
- Arrow keys didn't always advance the cursor in the sub-menu.

The manager's `_reconnect_mcp` resolves all three deterministically in
Python (cursor-free navigation: count down-arrows = position-in-list,
numbered selection `2` for Reconnect).

2026-05-07 update: extended to cover the worker-self-reconnect path via
`tm_reconnect_mcp`, after a leanspecs-ui-tm session bounced back from a
combined leanspecs+quartermaster MCP outage by self-driving while
tubemail stayed up. The previous skill text said workers can't
self-reconnect — that was wrong as long as tubemail is still alive.
