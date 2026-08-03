---
name: web-status-monitor
description: "Automate periodic checks of a public web page (government registry, status page, etc.) and deliver alerts via Hermes cron + messaging gateway."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Monitoring, Cron, Web-Scraping, Automation, Playwright]
    related_skills: [signal-gateway]
---

# Web Status Monitor via Hermes Cron

Use this pattern when you need to check a public webpage on a schedule and be notified only when something looks wrong (or always, for peace of mind).

## When to use

- Government business registry checks (e.g. Colorado SOS "Good Standing")
- Domain/SSL expiry monitoring
- Any page with a human-readable status field you want watched

## Key design decisions

1. **Direct URL vs navigation**: prefer the deepest direct URL you can find — skip the homepage and search flow. Saves fragility.
2. **Alert-only vs always-report**: alert-only (only message when status != expected) keeps noise down. Always-report gives monthly confirmation of good state.
3. **Delivery target**: must be a gateway-connected platform (Telegram, Signal, Discord, etc.). CLI-only cron output is saved locally but not pushed anywhere.

## Pinning down the page first

Registry sites are usually search-driven, and a search URL is not stable enough
to poll. Find the **direct detail URL** for the one record you care about and
keep that — most registries expose one once you have clicked through, carrying
an entity or file id. Record alongside it:

- the exact field you are watching (e.g. `Status`) and its healthy value
- any deadline the page implies, such as an annual-report month

Keep those specifics wherever you keep notes for that machine, not in this
skill: the technique is portable, the entity is yours.

## Cron prompt template

```
Use playwright to navigate to:
<the direct detail URL you pinned down above>

Extract the "<field>" field from the page.
If it is NOT "<healthy value>", send an urgent alert with the actual value and a link to the page.
If it IS "<healthy value>", send a brief monthly confirmation: "✓ <what you are watching> — <healthy value> as of [date]."
```

## Setting up the cron job

```python
# Example: 1st of each month at 9am
cronjob(
    action='create',
    name='registry status check',
    schedule='0 9 1 * *',
    prompt='...',   # use template above
    deliver='signal',   # or 'telegram', 'discord', etc.
    enabled_toolsets=['web']
)
```

## Navigation path (manual, if the direct URL breaks)

Write down the click path the first time you find the record, because the direct
URL is the thing most likely to rot:

1. the registry's home page
2. its business/entity search
3. the search term that finds your record
4. how many results it returns — and whether that is unambiguous
5. the link that reaches the detail page
6. the field you are watching

## Pitfalls

- Government registries are often legacy server-rendered apps: URL parameters
  matter, so do not strip any that look redundant
- Check whether your search term returns exactly one result. If it does, the
  navigation can be automated safely; if not, pin the direct URL instead
- The field is often visible on the results page as well as the detail page —
  the cheaper one is enough if you only need the status string
- Use Playwright rather than curl/requests where the site renders via JavaScript
- If the page implies a filing deadline, add a second reminder cron a month
  ahead of it — the monitor tells you the state, not that time is running out
