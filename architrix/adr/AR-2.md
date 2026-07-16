---
id: AR-2
title: End a worker session through the harness's own exit path, never a process kill
status: accepted
spec_refs: []
paths: ["skills/save-and-exit/SKILL.md", "references/memory-sweep.md"]
supersedes: null
superseded_by: null
created: 2026-07-16T22:46:44+00:00
updated: 2026-07-16T22:47:02+00:00
---

# AR-2: End a worker session through the harness's own exit path, never a process kill

## Context

Slash commands and process control belong to the Claude Code harness, not the agent. An agent printing /exit produces inert text; there is no claude-exit binary. In this ecosystem the only privileged actor that can act on a session's process is the tubemail manager, which owns the pty. So any skill that ends a session must route through the manager, and the question is only WHICH manager path.

tubemail offers two:

- tm_send(worker, "/exit") — /exit is a built-in harness command, and tm_send routes built-ins by having the manager type them into the session's pty. The session runs its own shutdown and the forwarder POSTs /goodbye.
- tm_stop(worker) — routes force_stop. The manager kills the Claude child, removes its PID file, unregisters, and exits.

The first draft of /save-and-exit on 2026-07-16 chose tm_stop, reasoning that a supervisor would restart a child that exited under it, and that tm_stop was the tool whose contract said "terminal". Both halves were wrong, and the refuting evidence was already on screen: tm_list_workers' own legend documents a first-class state, "exited cleanly - user /exit'd (forwarder POSTed /goodbye)". A typed /exit is a supported, recognized outcome, not an unsupervised death. The contract for tm_stop had been read carefully; the legend printed beside it had not.

Jesper caught it and rejected the design outright: the request for /save-and-exit is the memory sweep and then /exit typed in from the tubemail manager, nothing else, no process kill.

## Decision

A skill that ends a worker session uses the harness's own exit path — tm_send(worker="<name>", message="/exit") — and nothing else. tm_stop and every other kill path are forbidden for the ordinary close, and /save-and-exit names that prohibition explicitly rather than merely omitting it, because reaching for the tool labelled "terminal" is the natural mistake.

Address the WORKER, not <name>-manager. tm_send routes built-ins automatically. This is the mirror image of /save-and-clear's close, where "restart fresh" is NOT a built-in and therefore must be addressed to <name>-manager explicitly. One routing rule; the two skills sit on opposite sides of it, and each documents the contrast.

Force paths remain legitimate only for their stated purpose: recovering a worker that is hung or unreachable, where no clean shutdown is possible by definition.

## Consequences

Accepted:

- A clean exit is observable. The worker registers as "exited cleanly" in tm_list_workers, giving a non-destructive way to confirm the close did its job. A force_stop yields an "offline" worker indistinguishable from a crash: success and failure look identical, so nothing can be verified.
- The skill loses its ordering hazard. force_stop kills immediately, so the previous draft had to mandate printing the report BEFORE the call or lose it. A typed /exit waits for the prompt and cannot truncate output.
- A clean exit cannot be forced on a wedged session. If the harness never reaches its prompt the typed /exit never lands, and recovery is an explicit operator decision (tm_stop) rather than a skill's silent default. This is the intended trade: the skill's job is a clean shutdown, and an exit that looks like a crash is a failed exit.
- The manager process survives a clean /exit where force_stop also killed it. Anything depending on the manager outliving the session keeps working.

General lesson, recorded because it caused the error: "documented as terminal" is not the same as "correct". Prefer the gentlest mechanism that reaches the documented end state, and check the surrounding output before trusting an inference drawn from one contract in isolation.
