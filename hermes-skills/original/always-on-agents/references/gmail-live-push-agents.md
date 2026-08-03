# Gmail Live-Push Agents (IMAP IDLE) — Full Worked Example

Concrete recipes for building always-on Gmail assistants: near-real-time
triggering via IMAP IDLE (not polling, not Cloud Pub/Sub), OAuth2 XOAUTH2
auth against Gmail's IMAP server, 4-outcome LLM classifier cascade,
two-tier allow-list with live sent-mail watcher, and feedback learning
from user Gmail actions.

Load this when the target is Gmail specifically. For the general shape of
always-on daemons regardless of source, see the umbrella SKILL.md.

The template that inspired this doc lives at
`/home/hermes/.hermes/plans/2026-07-21_200000-email-agent-push.md` — a
2200-line implementation plan with copy-pasteable code for every piece
described below.

---

## 1. Why IMAP IDLE (not Gmail Pub/Sub, not polling)

| Mechanism | Latency | Needs public endpoint | Needs GCP Pub/Sub | Best for |
|-----------|---------|----------------------|-------------------|----------|
| Poll via Gmail API (`gmail search "is:unread newer_than:1h"`) | Latency = poll interval | No | No | Batch jobs, hourly cadence, Hermes cron |
| **IMAP IDLE on `imap.gmail.com:993`** | **Under 60 seconds** | **No** | **No** | **Always-on agent on a workstation/VM** |
| Gmail push via Cloud Pub/Sub | Seconds | Yes (HTTPS webhook) | Yes | Cloud server deployment with public URL |

**Default to IMAP IDLE** for user-owned always-on setups. It gives you the
push semantics of Pub/Sub without any of the infrastructure. Gmail supports
IDLE natively — the server sends `EXISTS` responses the moment new mail
arrives and holds the TCP connection open until then. Sub-60-second
latency comes for free with a 25-minute keepalive renewal.

---

## 2. XOAUTH2 authentication for Gmail IMAP

Gmail requires OAuth2 for IMAP; the XOAUTH2 SASL mechanism works with the
stdlib `imaplib`:

```python
import imaplib, json
from pathlib import Path
import google.oauth2.credentials
import google.auth.transport.requests

def get_access_token(token_file=Path.home()/".hermes/google_token.json") -> str:
    creds_data = json.loads(token_file.read_text())
    creds = google.oauth2.credentials.Credentials(
        token=creds_data["token"],
        refresh_token=creds_data.get("refresh_token"),
        token_uri="https://oauth2.googleapis.com/token",
        client_id=creds_data["client_id"],
        client_secret=creds_data["client_secret"],
    )
    if not creds.valid:
        creds.refresh(google.auth.transport.requests.Request())
        creds_data["token"] = creds.token
        token_file.write_text(json.dumps(creds_data, indent=2))
    return creds.token

def xoauth2_string(email: str, token: str) -> str:
    return f"user={email}\x01auth=Bearer {token}\x01\x01"

imap = imaplib.IMAP4_SSL("imap.gmail.com", 993)
auth = xoauth2_string("you@example.com", get_access_token())
imap.authenticate("XOAUTH2", lambda x: auth.encode())
imap.select("INBOX")
```

The Hermes google-workspace skill already stores the token at
`~/.hermes/google_token.json` and handles refresh. Reuse it — don't
create a second OAuth flow just for IMAP.

## 3. The IDLE loop (RFC 2177)

```python
IDLE_TIMEOUT = 25 * 60  # RFC allows 29 min max; renew earlier to be safe

while True:
    tag = imap._new_tag().decode()
    imap.send(f"{tag} IDLE\r\n".encode())
    imap.readline()                       # server sends "+ idling"
    imap.socket().settimeout(IDLE_TIMEOUT)

    notifications = []
    try:
        while True:
            line = imap.readline().decode(errors="replace").strip()
            if not line:
                break
            notifications.append(line)
            if "EXISTS" in line or "EXPUNGE" in line:
                break
    except TimeoutError:
        pass                              # normal — just renew IDLE

    imap.send(b"DONE\r\n")
    imap.readline()                       # server sends OK

    if any("EXISTS" in n for n in notifications):
        # fetch new UIDs, classify, act, label
        ...
```

### Gmail-specific pitfalls

- **Refresh the OAuth token every 55 minutes.** Google access tokens
  expire at 60 minutes. Break out of the IDLE inner loop, refresh, and
  reconnect.
- **Localized Sent folder names.** `[Gmail]/Sent Mail` is the standard
  name for English accounts. Fall back to `Sent` if SELECT returns
  non-OK. Same pattern for `[Gmail]/Trash`, `[Gmail]/All Mail`, etc.
- **X-GM-LABELS** is Gmail's IMAP extension for custom labels. To add:
  `imap.uid("STORE", uid, "+X-GM-LABELS", f'("{label_id}")')`. To move
  to trash: `imap.uid("STORE", uid, "+X-GM-LABELS", '("\\\\Trash")')`
  then set the `\Deleted` flag. If X-GM-LABELS misbehaves, fall back to
  the Gmail REST API (`users().messages().modify()`) for label ops and
  use IMAP only as the notification transport.
- **Reconnect with exponential backoff** on any exception. Cap at ~30s.

## 4. Two IDLE connections in parallel (INBOX + Sent)

To also watch what the user sends (e.g. keep a live allow-list of
"people I just replied to"), run a second IDLE loop on
`[Gmail]/Sent Mail` in a background thread:

```python
import threading
_live_sent: set[str] = set()
_lock = threading.Lock()

def sent_watcher():
    """Second IDLE connection; adds To/Cc addresses to _live_sent as user sends."""
    # ...same IDLE loop pattern as above, but SELECT [Gmail]/Sent Mail...
    # on EXISTS, FETCH new UIDs' TO/CC headers only:
    for uid in new_uids:
        _, data = imap.uid("FETCH", uid, "(BODY.PEEK[HEADER.FIELDS (TO CC)])")
        # parse addresses, add to _live_sent under _lock
        ...

threading.Thread(target=sent_watcher, daemon=True).start()
```

**Use `BODY.PEEK[HEADER.FIELDS (TO CC)]`** — do NOT fetch the full
RFC822 body when all you need is the recipient list. Saves bandwidth,
and PEEK doesn't mark the message as seen.

Each thread owns its own IMAP connection and reconnects independently.
Never share an IMAP object between threads.

---

## 5. Two-tier allow-list

For triage agents, allow-list matches beat LLM calls every time —
cheaper, deterministic, faster. Split into two tiers:

- **Tier A — auto-important**: hard-coded business relationships (e.g.
  rows from an authoritative Google Sheet — the people you are under
  contract with). A match bypasses the LLM entirely and short-circuits to
  IMPORTANT.
- **Tier B — not-spam**: broader "people I know" set (Google Contacts,
  addresses I've emailed recently). A match doesn't force IMPORTANT — it
  just removes SPAM from the LLM's option set.

### Sourcing tier B — live watcher, NOT rolling window

If the user wants "check sent emails of the day for new people to add to
the allow list," the naive answer is a 15-minute cron that rebuilds from
the last 30 days of Sent. **This is wrong.** 29 of those 30 days were
already processed on every prior run.

Right shape:
- **Google Contacts** — rebuild once daily via the People API. Contacts
  are stable; no push API exists.
- **Live sent addresses** — the background IMAP IDLE thread on
  `[Gmail]/Sent Mail` (section 4). Adds addresses to an in-memory set
  as they arrive. No file cache, no lookback window. On daemon restart
  the set starts empty; daily Contacts rebuild covers the persistent
  baseline, and the live thread covers current-session replies within
  seconds.

### Sourcing tier A from a Google Sheet

```python
from googleapiclient.discovery import build
svc = build("sheets", "v4", credentials=creds)
for tab in ["Members", "Prospects"]:          # whatever your sheet calls them
    result = svc.spreadsheets().values().get(
        spreadsheetId="<your-sheet-id>",
        range=f"'{tab}'!A:B",             # col A = Name, col B = Email
    ).execute()
    for row in result.get("values", [])[1:]:  # skip header
        name  = row[0].strip() if len(row) > 0 else ""
        email = row[1].strip() if len(row) > 1 else ""
        ...
```

Inspect tab structure first with `spreadsheets().get()` (or the
`sheets_get_metadata` MCP tool if in a Hermes session). Multi-tab
sheets are common.

### Matching senders against the allow-list

The Gmail `From` header comes in two forms — `"Display Name" <addr@x.com>`
or bare `addr@x.com`. Extract both and check both:

```python
import re
m = re.search(r'<([^>]+)>', from_header)
addr    = m.group(1).lower().strip() if m else from_header.lower().strip()
display = re.sub(r'<[^>]+>', '', from_header).strip().strip('"\'').lower()

if addr in tier_a["emails"] or display in tier_a["names"]:
    return "tier_a"                       # auto-important, skip LLM
if addr in tier_b["emails"] or display in tier_b["names"] or addr in live_sent:
    return "tier_b"                       # not-spam, restricted LLM prompt
return None                               # unknown, full LLM cascade
```

Name matching catches the case where a known person emails from a new
address. False-positive risk is low because collisions on full-name
matches are rare.

---

## 6. 4-outcome classifier prompt

Two-way spam/important is not enough for a real inbox. Use 4 outcomes:

- **SPAM** — auto-trash / archive
- **IMPORTANT** — notify user, needs their attention
- **NOTIFICATION** — legitimate but no action needed (receipts, digests,
  calendar reminders, 2FA codes, automated status updates)
- **GREY** — ambiguous, kick to the user

Prompt structure (each section is a docstring block, combined at build
time):

```python
SYSTEM_BASE = "You are an email classifier for <user>. Classify each email into ONE category:"

CATEGORY_SPAM = """
=== SPAM — clearly any of: ===
- New line of credit / loan / financial services spam
- "Let us do SEO / marketing / social" cold pitches
- Domain / hosting upsell from unknown registrars
- Cold "I found your website" outreach
- Phishing, scam, prize winnings
- Generic PR pitches with no real connection
Real spam examples from user's Trash:
{spam_examples}
"""

CATEGORY_IMPORTANT = """
=== IMPORTANT — requires <user>'s attention or a reply: ===
- Someone asking about attending a workshop/event
- Someone wanting to hire the user
- Existing participant/client/partner following up
- Legal/billing notice from a known institution
- Anything from @<user's domain>
- Real human writing about their situation related to user's work
- Reply to something user previously sent
- Anything time-sensitive that only user can decide
Real important examples:
{important_examples}
"""

CATEGORY_NOTIFICATION = """
=== NOTIFICATION — keep but no action needed: ===
- Receipts and order confirmations from services user uses
- Calendar invites/reminders from known systems
- Automated status updates (GitHub, Stripe, Google, hosting)
- Newsletters user deliberately subscribed to
- Delivery / shipping notifications
- 2FA / security alerts from services user uses
- Read-only informational updates

NOTIFICATION differs from SPAM: it comes from a service user uses/subscribed to.
NOTIFICATION differs from IMPORTANT: no reply or decision is needed.
"""

CATEGORY_GREY = """
=== GREY — use ONLY when you genuinely cannot tell: ===
- Ambiguous cases where you cannot commit
Do NOT use GREY as a way to avoid choosing — commit whenever you can defend it.
"""

RESPONSE_FORMAT = """
Reply with exactly two lines:
VERDICT: <SPAM|IMPORTANT|NOTIFICATION|GREY>
REASON: <one sentence max>
"""
```

**Critical**: the "do NOT use GREY to avoid choosing" instruction. Without
it, Haiku dumps borderline cases into GREY and blows the Opus budget.

### Restricted prompt for allow-listed senders

When a tier-B sender comes through, structurally remove the SPAM option:

```python
def build_system_prompt(allow_spam: bool = True) -> str:
    parts = [SYSTEM_BASE]
    if allow_spam:
        parts.append(CATEGORY_SPAM.format(...))
    parts.extend([CATEGORY_IMPORTANT.format(...), CATEGORY_NOTIFICATION, CATEGORY_GREY])
    parts.append(RESPONSE_FORMAT if allow_spam else RESPONSE_FORMAT_NO_SPAM)
    if not allow_spam:
        parts.insert(1, "NOTE: This sender is in <user>'s contacts. "
                        "They are NOT spam. Do not use the SPAM category.")
    return "\n\n".join(parts)
```

Structural removal (omit the section entirely + adjust response format)
is more reliable than negative instruction ("please don't classify as
spam"). Verified across Haiku/Sonnet/Opus.

---

## 7. Cascade escalation

```python
def _run_cascade(system, user_msg, allow_spam=True):
    valid_final = {"spam","important","notification"} if allow_spam else {"important","notification"}
    chain = []

    # Tier 1: Haiku
    v, r = call_model("claude-haiku-4-5", system, user_msg)
    chain.append(f"haiku:{v}")
    if v in valid_final:
        return {"verdict": v, "chain": chain, "reasoning": r}

    # Tier 2: Sonnet
    v, r = call_model("claude-sonnet-4-5", system, user_msg)
    chain.append(f"sonnet:{v}")
    if v in valid_final:
        return {"verdict": v, "chain": chain, "reasoning": r}

    # Tier 3: Opus with extended thinking (budget mode)
    v, r = call_model("claude-opus-4-5", system, user_msg, budget_tokens=1024)
    chain.append(f"opus:{v}")
    return {"verdict": v, "chain": chain, "reasoning": r}  # even GREY is final here
```

Cost estimate for 2-3 emails/day: under $0.15/week. Scales linearly with
volume; most cost concentrates on the hardest ~5% of decisions.

---

## 8. Feedback loop from Gmail actions

Bind observable user actions to corpus updates. Run as a daily cron —
human signal accumulates on human timescales.

| User action on Hermes-labelled email | Corpus bucket updated |
|--------------------------------------|----------------------|
| Deletes a Hermes/Spam email | Confirmed spam |
| Marks Hermes/Important as unread | Confirmed important (needs action) |
| Replies to any Hermes-labelled email (any thread with SENT label) | Confirmed important |
| Leaves Hermes/Important read AND unreplied for N days | **Confirmed notification** (looked at it, no action needed) |

The last row is the subtle-but-valuable one. It's how the agent learns
to distinguish "important" from "notification" over time. Also relabel
the Gmail message: remove Hermes/Important, add Hermes/Notification.

### Bootstrap corpus from existing Gmail signal

Before writing the classifier, harvest what the user already implicitly
labelled:
- **Trash (last 30 days)** → confirmed spam corpus
- **Inbox unread** → ambiguous / left-for-review corpus (user's implicit
  "handle later" queue)

Sample from these in the few-shot prompt slots. Cap at ~100 spam, 30
important, 30 notification to keep prompts bounded.

---

## 9. Rollout: monitor mode → live mode

Week 1: `monitor_mode=true`, `training_week=true`:
- Apply labels only. Do NOT move anything to trash.
- Signal notify on EVERY email with full cascade chain and reasoning.

Week 2+: flip both flags to false:
- Move Hermes/Spam to Trash.
- Signal notify only on IMPORTANT and GREY (silent on SPAM and
  NOTIFICATION).

Config lives in a JSON file the daemon reloads on every event. Flipping
the flag takes effect within seconds — no restart needed.

---

## 10. Dashboard: Google Sheet with two tabs

- **Activity Log** — one row per processed email: timestamp, from,
  subject, verdict, cascade chain, reasoning, monitor-mode flag.
  Appended by the daemon after every classification.
- **Weekly Summary** — one row per week: total processed, counts by
  verdict, cascade escalation percentages, allow-list bypass count.
  Appended by a Monday-morning cron.

Wrap the Sheet append in try/except so a transient Sheets API failure
doesn't crash the classifier — log the failure to the local
actions.jsonl and continue.

---

## 11. systemd unit files

Main daemon (INBOX watcher + Sent watcher live in the same process):

```ini
# ~/.config/systemd/user/hermes-email-agent.service
[Unit]
Description=Hermes Email Agent — IMAP IDLE daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/user/.hermes/email-agent/imap_daemon.py
WorkingDirectory=/home/user/.hermes/email-agent
Restart=always
RestartSec=15
Environment="ANTHROPIC_API_KEY=sk-ant-..."
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=default.target
```

Daily maintenance timer (allow-list rebuild + feedback learner):

```ini
# ~/.config/systemd/user/hermes-email-daily.service
[Unit]
Description=Hermes Email — daily maintenance

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /home/user/.hermes/email-agent/build_allowlist.py
ExecStart=/usr/bin/python3 /home/user/.hermes/email-agent/feedback_learner.py
Environment="ANTHROPIC_API_KEY=sk-ant-..."
```

```ini
# ~/.config/systemd/user/hermes-email-daily.timer
[Unit]
Description=Run Hermes email daily maintenance at 3am

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=5min
Persistent=true
Unit=hermes-email-daily.service

[Install]
WantedBy=timers.target
```

Install:
```bash
mkdir -p ~/.config/systemd/user
systemctl --user daemon-reload
systemctl --user enable --now hermes-email-agent.service hermes-email-daily.timer
systemctl --user status hermes-email-agent.service
journalctl --user -u hermes-email-agent.service -f
```

For the daemon to keep running when nobody is logged in:
```bash
loginctl enable-linger $USER
```

---

## Related

- Umbrella skill: `always-on-agents` (general shape, deployment,
  cascade patterns).
- `google-workspace` skill: OAuth setup, Gmail/Sheets/Contacts API
  wrappers. The token at `~/.hermes/google_token.json` from that skill
  is exactly what the IMAP daemon reads.
- Gmail search operators: `google-workspace` skill has
  `references/gmail-search-syntax.md`.
- If you have built one of these before, the plan you wrote at the time is
  usually under `~/.hermes/plans/` — worth rereading before starting another.
