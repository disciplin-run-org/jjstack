---
name: always-on-agents
description: "Design always-on daemons that react to push events (IMAP IDLE, watchers) instead of polling. Systemd services, cascade classifiers, monitor→live rollout."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [daemon, systemd, imap-idle, push, agent, classifier, cascade, rollout]
    related_skills: [google-workspace, plan]
---

# Always-On Agents

Design and deploy long-lived processes that react to external push events
within seconds — without polling loops, without public HTTPS endpoints, and
without cloud infrastructure. Covers the shape of the daemon, deployment
via systemd, LLM-classifier cascades when the agent needs to make
per-event decisions, and the monitor→live rollout pattern for destructive
actions.

Load this when the user asks for anything like:
- "React within N seconds when X happens"
- "Watch my email/directory/queue and do Y when Z arrives"
- "I don't want to poll every N minutes"
- "Notify me when …"
- "Always-on assistant that triages/labels/routes …"

The exemplar this skill grew from is a Gmail triage agent that classifies
each incoming email in under 60 seconds via IMAP IDLE, with a 3-model LLM
cascade behind an allow-list. Same shape works for file watchers,
message-queue consumers, webhook receivers, or any watch-and-react loop.

## Reference sub-docs

- `references/gmail-live-push-agents.md` — full worked example: IMAP IDLE
  with Gmail (XOAUTH2), two-tier allow-lists, live sent watcher, 4-outcome
  classifier prompt, feedback learning from Gmail actions, dashboard.
  Load this first when the target is Gmail specifically — it has
  copy-pasteable code for every layer.

---

## Core shape of an always-on agent

```
┌─────────────────────────────────────────────────┐
│  systemd user service (Restart=always)          │
│  ┌───────────────────────────────────────────┐  │
│  │  Main event loop                          │  │
│  │  ├─ Connect to push source (IMAP/WS/...)  │  │
│  │  ├─ Reload config from disk each event    │  │
│  │  ├─ Wait for push notification            │  │
│  │  ├─ Fetch what changed                    │  │
│  │  ├─ Optional: allow-list pre-filter       │  │
│  │  ├─ Optional: LLM classifier cascade      │  │
│  │  ├─ Take action (label/notify/move/...)   │  │
│  │  └─ Log to append-only file + dashboard   │  │
│  │  On error → exponential backoff reconnect │  │
│  └───────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────┐  │
│  │  Background thread(s) for auxiliary       │  │
│  │  live state (e.g. sent-mail watcher       │  │
│  │  that updates in-memory allow-list)       │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘

Companion:
  systemd .timer  →  daily maintenance job
                     (rebuild allow-lists, run feedback learner,
                      rotate logs, refresh caches)
```

## Choose your trigger, don't poll if you can push

Prefer push mechanisms over polling. Poll only if there is truly no push
option. Table of common triggers:

| Source | Push mechanism | Latency |
|--------|---------------|---------|
| IMAP mailbox | IMAP IDLE (RFC 2177) | <60s |
| Filesystem | `inotify` (Linux) / FSEvents (macOS) — via `watchdog` Python lib | ms |
| Message queue | native consumer callback (Kafka, RabbitMQ, Redis Streams) | ms |
| Webhooks | need public endpoint (tunnel or hosted) | ms |
| Git repo | webhook > polling; use `git ls-remote` polling only if forced | seconds vs minutes |
| HTTP API without push | poll with `If-Modified-Since` / ETag if supported | poll interval |

Anti-pattern spotted repeatedly: **rolling-window polling** ("every 15 min,
process last 30 days of X"). On every run you re-process ~99% of the same
items. Replace with (1) a persistent full-baseline job that runs rarely
(daily), plus (2) a live incremental watcher for the delta. See the Gmail
reference doc for the concrete example.

## LLM classifier cascade for per-event decisions

If the agent needs to make an LLM-quality decision on each event, don't
call the biggest model every time. Cascade:

```
Cheap+fast model   →  IF verdict is confident, USE IT and stop
      ↓ only on GREY
Medium model       →  IF confident, USE IT and stop
      ↓ only on GREY
Best model (thinking mode, small budget)  →  final verdict
      ↓ if still GREY
Escalate to human
```

Rules:
- Escalate ONLY on the "grey" / "uncertain" outcome. Never re-verify a
  confident answer from a lower tier — it doubles cost with no benefit.
- All tiers share the same prompt for label consistency.
- Force the model to earn its GREY: "Do NOT use GREY as a way to avoid
  choosing." Otherwise the cheap tier defaults to GREY and blows your
  expensive-tier budget.
- If a whitelist/allowlist can pre-filter obvious cases, do that BEFORE
  calling any model. LLM tokens are always more expensive than a dict
  lookup.
- Use extended-thinking / budget-tokens mode on the top-tier model — a
  small budget (~1024 tokens) is usually enough to break ties.

## Allow-list tiers

For triage agents, allow-lists dramatically reduce LLM calls:
- **Tier A — hard override**: known-safe/known-important senders bypass
  the LLM entirely.
- **Tier B — restrict-the-prompt**: known-not-hostile senders still go
  through the LLM, but with a restricted prompt that removes the
  destructive outcome (e.g. "not spam, so choose IMPORTANT or
  NOTIFICATION or GREY only"). Structural removal of the option is more
  reliable than instruction ("please don't classify as spam").

Build tier B from two sources: (a) a persistent daily-rebuilt corpus
(Contacts, member lists), and (b) a **live in-memory watcher** that
adds entries in real time as new events occur (e.g. addresses the user
just sent mail to). Never combine a lookback window with a live watcher
— pick one; the lookback duplicates work the watcher already does.

## Multi-outcome verdicts: separate "kept but no action" from "important"

Two-way spam/important is usually not enough for a real inbox. A 4-outcome
schema works better:
- **DELETE / SPAM** — the destructive action
- **ACT / IMPORTANT** — user must handle
- **KEEP / NOTIFICATION** — legitimate but no action needed (receipts,
  digests, calendar reminders, 2FA codes, subscribed newsletters)
- **HUMAN / GREY** — ambiguous, kick to the user

Without a NOTIFICATION bucket, you notify on every Stripe receipt. Define
NOTIFICATION by contrast in the prompt:
- "NOTIFICATION differs from SPAM: it comes from a service the user uses."
- "NOTIFICATION differs from IMPORTANT: no reply or decision is needed."

## Feedback loop: learn from user actions

The user's ongoing behaviour on the agent's output is high-quality
training signal. Bind observable actions to corpus buckets:
- User deleted an item the agent flagged as X → confirmed X.
- User re-flagged / reopened / marked-unread → agent was wrong; update
  corpus with the corrected label.
- User replied / acted → confirmed important.
- User left it alone for N days → confirmed "notification" (kept but no
  action needed).

Run the feedback scanner as a daily job, not a high-frequency one. Human
signal accumulates on human timescales; scanning every 15 minutes catches
the same events over and over. Cap corpus size per bucket (~100 items)
to keep few-shot prompts bounded.

## Deployment: systemd user service

For always-on Python daemons on Linux/macOS workstations, `systemd --user`
is the right home. NOT Hermes cron (cron is for bounded, scheduled work).
NOT `nohup ... &` (no restart-on-crash, no lifecycle, no logs).

Minimal unit for the daemon:
```ini
# ~/.config/systemd/user/<agent>.service
[Unit]
Description=<agent> — always-on
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/<user>/<agent>/daemon.py
Restart=always
RestartSec=15
Environment="ANTHROPIC_API_KEY=sk-ant-..."
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=default.target
```

Companion timer for daily maintenance:
```ini
# ~/.config/systemd/user/<agent>-daily.timer
[Unit]
Description=Daily maintenance for <agent>

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=5min
Persistent=true            # catches up if the machine was off at 3am
Unit=<agent>-daily.service

[Install]
WantedBy=timers.target
```

Install:
```bash
mkdir -p ~/.config/systemd/user
# write the .service and .timer files
systemctl --user daemon-reload
systemctl --user enable --now <agent>.service <agent>-daily.timer
systemctl --user status <agent>.service
journalctl --user -u <agent>.service -f
```

For the daemon to keep running when the user is not logged in:
```bash
loginctl enable-linger $USER
```

## Config reload on each event — no restart needed

Read the config JSON at the top of each event-handler pass, not just at
startup. That way the user can flip flags (monitor mode ↔ live mode,
notification verbosity) by editing the JSON and the change takes effect
on the next incoming event — usually within seconds. This is the pattern
that makes the monitor→live rollout below possible without restarts.

## Rollout pattern for destructive actions

Never ship a new agent straight to auto-delete / auto-reply / auto-modify.
Stage the rollout with a config flag:

- **Week 1 — monitor mode**: apply labels/tags only. Skip every
  destructive step. Send verbose notifications with the full decision
  path (classifier chain, reasoning, allow-list hits). Let the user
  spot-check every decision.
- **Week 2+ — live mode**: enable destructive actions. Trim notifications
  to only the ones the user must react to.

One flag, one flip:
```json
{
  "monitor_mode": true,      // week 1
  "training_week": true      // week 1: notify on everything
}
```

The daemon reloads config on each event (see previous section), so the
flip takes effect within seconds. No downtime, no restart. If the user
sees a mistake after switching to live mode, they can flip back to
monitor mode instantly.

## Logging and audit

Two-track logging:
1. **Structured append-only log** (`actions.jsonl`, one JSON per line).
   Every processed event: what came in, what the agent decided, what
   action was taken, the reasoning. This is your permanent audit trail.
2. **Human-readable dashboard** (Google Sheet, small SQLite + web UI,
   or plain HTML dumped to disk). Updated on every event by the daemon
   plus a weekly summary row by the daily/weekly cron.

For the dashboard, wrap the update call in try/except so a transient
Sheets/DB failure doesn't crash the daemon's main loop. Log the failure
to the local .jsonl and continue.

## Pitfalls

- **Don't put the daemon in Hermes cron**. Hermes cron jobs are for
  bounded scheduled work (once, or every N minutes). An always-on daemon
  needs systemd (or equivalent lifecycle manager) to get restart-on-crash,
  log rotation, and proper signal handling.
- **Refresh OAuth tokens BEFORE they expire**, not on the 401. Break out
  of your inner loop every N minutes (55min for Google, whose access
  tokens expire at 60min) and refresh proactively.
- **Reconnect with exponential backoff, capped**. Network blips are
  routine. Uncapped backoff means the daemon might sleep for hours after
  a bad afternoon.
- **Two IDLE connections need two threads**. IMAP IDLE blocks the
  connection. If you need to watch INBOX and Sent simultaneously, spawn a
  second thread with its own IMAP connection. Coordinate shared state
  behind a `threading.Lock()`.
- **Don't fetch full bodies when metadata will do**. For allow-list
  updates you only need To/Cc headers — use
  `BODY.PEEK[HEADER.FIELDS (TO CC)]` (also doesn't mark the message
  as seen).
- **Log to journald AND to a file inside the agent's data dir**.
  journald is great for immediate `journalctl -f`, but the local file
  survives log rotation and is what feedback learners / diagnostics
  actually parse.

## Related skills

- `google-workspace` — Gmail/Sheets/Calendar/Drive/Contacts API and OAuth
  setup. Required for any Gmail-based always-on agent.
- `plan` — write the full implementation plan for the agent before
  building it. Multi-tier agents with cascades, feedback loops, and
  rollout phases are worth planning in detail up front.

## Anti-patterns spotted in real sessions

- **"Poll every 15 minutes for last 30 days of X"** — you re-read 29 days
  of already-processed data on every run. Replace with (a) daily full
  rebuild + (b) live incremental watcher.
- **"Verify the cheap model's answer with the expensive model"** — doubles
  cost with no benefit. Trust the confident answer; only escalate the
  GREY / uncertain ones.
- **"Just run the daemon in a `while true; do python daemon.py; done`
  loop under nohup"** — you lose crash logs, lifecycle control, boot
  behaviour, and the ability to stop it cleanly. Use systemd.
- **"Restart the daemon whenever config changes"** — instead, reload
  config from disk on each event. Zero downtime, and users can tune the
  agent without touching the process.
