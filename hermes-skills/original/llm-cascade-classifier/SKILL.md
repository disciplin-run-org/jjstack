---
name: llm-cascade-classifier
description: "Multi-tier LLM classification cascade: cheap fast model first, escalate grey-area to smarter models. Haiku → Sonnet → Opus pattern with 3-outcome classification (spam/important/grey) and pre-classifier allow-lists."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [classification, spam-filter, cascade, haiku, sonnet, opus, LLM, cost-optimization, pre-classifier]
    related_skills: [gmail-automation, systematic-debugging]
---

# LLM Cascade Classifier

A cost-efficient classification pattern: run a cheap, fast model first.
Escalate only genuine grey-area cases to progressively smarter (and more
expensive) models. Works for any 3-class classification problem.

Load this skill when:
- Building a classifier that must be cheap per-call but accurate on hard cases
- The classification has a meaningful "uncertain" category worth escalating
- You want to minimize expensive model calls without sacrificing accuracy

## References

- `references/cascade-patterns.md` — implementation patterns, prompt design, few-shot corpus management

---

## The Core Pattern

```
Input
  |
  v
[Tier 1: Fast cheap model — e.g. Haiku]
  3 outcomes: A / B / GREY
  |
  If A or B -> done (fast path, most traffic here)
  If GREY -> escalate
              |
              v
         [Tier 2: Smarter model — e.g. Sonnet]
           3 outcomes: A / B / GREY
           |
           If A or B -> done
           If GREY -> escalate
                       |
                       v
                  [Tier 3: Best model — e.g. Opus, budget mode]
                    3 outcomes: A / B / GREY
                    |
                    GREY here = final verdict (human reviews)
```

The key insight: **most inputs are obvious**. ~80% of real-world classification
problems have clear-cut cases that any model can handle. Only the ambiguous 10-20%
need escalation to Sonnet. Only the ambiguous-of-ambiguous (~2-5%) need Opus.

---

## When to Use 3 Outcomes vs. 2

**3 outcomes (A / B / GREY):** Use when:
- False positives in either direction have real cost (e.g. deleting real email)
- A human review path exists for uncertain cases
- The problem has genuine ambiguity at the margins

**2 outcomes (A / B):** Use when:
- One class is a safe default on uncertainty ("when in doubt, keep")
- No human review path; every email must be acted on

For email triage: always 3 outcomes. The GREY -> NeedsReview -> human path
is the safety valve that prevents the agent from confidently deleting real mail.

---

## Prompt Design

All three tiers use the **same system prompt**. This is important:
- Tier 1 sees the same criteria as Tier 3 — consistency
- Escalation is not "re-ask a better question"; it's "get a better judgment on the same question"
- The smarter model naturally handles nuance the cheaper one couldn't resolve

**Response format:** Force a parseable single-line response:
```
VERDICT: <A|B|GREY>
REASON: <one sentence>
```

Parse defensively — default to the safest class on any parse failure.

**Few-shot examples:** Include real examples from a corpus of known-classified
cases. Load N examples from each class (e.g. 5 spam, 2 important). Rotate
examples randomly on each call to avoid over-fitting to a fixed set.

---

## Pre-Classifier Allow-List (Tier 0)

Before any LLM call, check a local JSON cache of known-important senders.
This is free (no API call, no latency) and catches the highest-confidence cases.

```python
def check_allowlist(from_addr: str) -> str | None:
    """Return source string if sender matches allow-list, else None."""
    al = json.loads(ALLOWLIST_FILE.read_text())
    emails = al.get("emails", {})
    names  = al.get("names", {})

    m = re.search(r'<([^>]+)>', from_addr)
    addr    = m.group(1).lower().strip() if m else from_addr.lower().strip()
    display = re.sub(r'<[^>]+>', '', from_addr).strip().strip('"').lower()

    if addr    in emails: return emails[addr]
    if display in names:  return names[display]
    return None

def classify(from_addr, subject, body) -> dict:
    source = check_allowlist(from_addr)
    if source:
        return {"verdict": "important", "chain": [f"allowlist:{source}"],
                "reasoning": f"Sender in {source}"}
    # ... LLM cascade ...
```

Allow-list sources (rebuild daily):
- Google Contacts
- To/Cc from Sent mail last 30 days (people you've replied to are always important)
- External lists (e.g. a Google Sheet of known contacts)

---

## Implementation

```python
import anthropic, json, os, random
from pathlib import Path

CLIENT = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

TIERS = [
    {"model": "claude-haiku-4-5",   "budget_tokens": 0},
    {"model": "claude-sonnet-4-5",  "budget_tokens": 0},
    {"model": "claude-opus-4-5",    "budget_tokens": 1024},  # extended thinking
]

def call_model(model: str, system: str, user_msg: str, budget_tokens: int = 0) -> tuple[str, str]:
    kwargs = dict(model=model, max_tokens=60, system=system,
                  messages=[{"role": "user", "content": user_msg}])
    if budget_tokens:
        kwargs["thinking"] = {"type": "enabled", "budget_tokens": budget_tokens}
        kwargs["max_tokens"] = budget_tokens + 60
    resp = CLIENT.messages.create(**kwargs)
    # skip thinking blocks, take first text block
    text = next((b.text for b in resp.content if getattr(b, "type", "") == "text"), "")
    verdict = "grey"
    reason  = text
    for line in text.splitlines():
        if line.lower().startswith("verdict:"):
            v = line.split(":", 1)[1].strip().lower()
            if v in ("spam", "important", "grey"):
                verdict = v
        elif line.lower().startswith("reason:"):
            reason = line.split(":", 1)[1].strip()
    return verdict, reason

def classify_cascade(system: str, user_msg: str) -> dict:
    chain = []
    for tier in TIERS:
        try:
            v, r = call_model(tier["model"], system, user_msg, tier["budget_tokens"])
        except Exception as e:
            v, r = "grey", f"{tier['model']} error: {e}"
        chain.append(f"{tier['model'].split('-')[1]}:{v}")  # e.g. "haiku:spam"
        if v != "grey":
            return {"verdict": v, "chain": chain, "reasoning": r}
    # All tiers said grey -> final verdict is grey (human reviews)
    return {"verdict": "grey", "chain": chain, "reasoning": r}
```

---

## Logging and Audit Trail

Log every classification decision:
```python
entry = {
    "at": datetime.now(timezone.utc).isoformat(),
    "from": from_addr,
    "subject": subject,
    "verdict": result["verdict"],
    "chain": result["chain"],   # e.g. ["haiku:grey", "sonnet:spam"]
    "reasoning": result["reasoning"],
}
with open(ACTIONS_LOG, "a") as f:
    f.write(json.dumps(entry) + "\n")
```

The `chain` field shows which models ran and what each decided. This is
invaluable for debugging and tuning. Show it in notifications during the
training period.

---

## Corpus Management (Few-Shot Training)

Keep a `corpus.json` of confirmed examples:
```json
{
  "spam":    [{"from": "...", "subject": "...", "snippet": "..."}],
  "review":  [{"from": "...", "subject": "...", "snippet": "..."}]
}
```

**Bootstrap:** Read 30 days of Trash (confirmed spam the user deleted) and
current unread inbox (items left for review). This seeds the classifier with
real examples immediately.

**Grow via feedback:** Daily, scan for:
- Spam-labelled items the user deleted -> confirmed spam
- Important-labelled items the user marked unread -> confirmed important
- Threads the user replied to -> confirmed important

**Cap size** to prevent prompt bloat (e.g. last 100 spam, last 30 important).

---

## Cost Profile (claude-haiku-4-5 / sonnet / opus)

Approximate at 2-3 emails/day with 80% obvious, 15% grey-to-sonnet, 5% grey-to-opus:

| Tier | % of traffic | Cost/call | Weekly cost |
|------|-------------|-----------|-------------|
| Allow-list | ~30% | $0 | $0 |
| Haiku | ~50% of LLM | ~$0.001 | ~$0.01 |
| Sonnet | ~15% of LLM | ~$0.003 | ~$0.01 |
| Opus | ~5% of LLM | ~$0.01 | ~$0.005 |
| **Total** | | | **~$0.03/week** |

At higher volumes (50 emails/day): ~$0.30/week. Still cheap.

---

## Monitor Mode (Safe Rollout)

Always run in monitor mode for the first week:
- Classify and label but take NO destructive actions (no trash, no delete)
- Notify on every email including spam, showing the full cascade chain
- Review accuracy in the audit log before enabling live mode

Store as a config flag (`monitor_mode: true/false`). Reload on every event
so you can flip it without restarting the daemon.

---

## Pitfalls

1. **Default to the safest class on any model error.** Never let an exception
   cause a false-spam classification. "important" is always the safe default.

2. **3 outcomes per tier, not 2.** If you only give models binary choices
   (spam/not-spam), there is no escalation signal. The GREY category is what
   drives escalation — without it, tier 1 handles everything with lower accuracy.

3. **Rotate few-shot examples.** Using the same fixed examples every call risks
   the model pattern-matching on them. Sample randomly from the corpus.

4. **Opus thinking mode needs `max_tokens = budget_tokens + 60`** — the thinking
   tokens count against max_tokens, so if you set max_tokens=60 with a 1024-token
   thinking budget you'll get an error. Always add the budget to max_tokens.

5. **The system prompt must name all three outcome words explicitly.** If GREY
   is not named in the prompt, some models will never return it and everything
   ends up in Haiku's binary output.
