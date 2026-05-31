---
name: browse
version: 0.1.0
description: |
  Adaptive web-page reader: try the fastest backend first, fall back to
  slower-but-more-capable backends on failure, learn the winning method
  per domain, cache it in browse-routes.json. Backends in order: curl
  (fastest, no JS, no auth), cookied headless chrome (JS + your session
  cookies), claude-in-chrome MCP (real browser tab, anti-bot stealth),
  Playwright via gstack browse daemon (full automation, slowest).
  Trigger on: "browse", "read this page", "fetch the URL", "scrape this",
  "get the page content", "load this URL", "what's on this page",
  "read the docs at <url>".
  Do NOT trigger for: file reads (use Read), git operations, or anything
  that does not start from a URL. For browser-driven QA testing of a
  deployed app (clicking, asserting, screenshots), use /qa, /qa-only,
  or /browse-daemon-direct. This skill is for READING; QA skills are for
  TESTING.
allowed-tools:
  - Read
  - Bash
  - WebFetch
---

# /browse - adaptive page reader

Single entry point for "I need the content of a URL." Picks the cheapest
backend that can actually deliver the page, falls back on failure, and
remembers the winning method per domain so the next visit skips the
fallback chain.

## The four backends, in order

| # | Backend | When it works | Cost | Speed |
|---|---------|---------------|------|-------|
| 1 | **curl** | Static HTML, public pages, API endpoints | Lowest | Fastest (~100ms) |
| 2 | **cookied chrome** | Pages behind a cookie/session (Google, GitHub when authed) | Low | Fast (~1-2s) |
| 3 | **claude-in-chrome MCP** | Anti-bot pages, paywalls, JS-heavy SPAs that fight headless | Medium | Medium (~3-5s) |
| 4 | **Playwright (gstack browse)** | Everything that fights the first three; full JS rendering | High | Slow (~5-10s) |

Try (1). If it returns HTTP 4xx/5xx or content is too short to be a real
page, try (2). And so on. The first backend to return a real page wins.

## Cache: `~/.jjstack/browse-routes.json`

Exact-match domain to method. Updated on every successful fetch. Schema:

```json
{
  "updated": "2026-05-30T...",
  "routes": {
    "github.com": "curl",
    "docs.anthropic.com": "curl",
    "twitter.com": "claude-in-chrome",
    "linkedin.com": "playwright"
  }
}
```

When the cache has an entry for the host, skip backends below it. Try
the cached method first; on failure, fall through the chain starting
from the next backend down.

## Phase 1: Resolve the URL and check the cache

Extract the host from the URL. Read `~/.jjstack/browse-routes.json`. If
a cached method exists for the host, start the chain from that method.

## Phase 2: Try the chain

For each backend in the chain, starting at the cached method (or curl
if none cached):

1. Invoke the backend with the URL.
2. Validate the response:
   - HTTP 2xx
   - Content length >= 500 bytes (raises on near-empty pages, common
     for anti-bot blocks)
   - Body does not match obvious block patterns ("Access Denied",
     "Just a moment...", "Please verify you are human")
3. If validated, success. Record the winning method in the cache.
4. If failed, log the failure and try the next backend down.

If all four backends fail, return the best failure response with
diagnostic info (which backends were tried, what each returned).

## Backend invocation details

### Backend 1: curl

```bash
curl -sL --max-time 15 -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" "<URL>"
```

Sets a real user-agent header (anti-bot heuristics often block default
curl). 15-second timeout.

### Backend 2: cookied chrome

Uses `setup-browser-cookies` + `PLAYWRIGHT_CHANNEL=chrome` to drive
real-Chrome-with-your-cookies headless. The gstack browse daemon
supports this via the chrome channel.

### Backend 3: claude-in-chrome MCP

Open a tab via `mcp__claude-in-chrome__tabs_create_mcp(url=<URL>)`,
wait for load, then `mcp__claude-in-chrome__read_page` to extract
content. Close the tab after.

### Backend 4: Playwright via gstack browse daemon

The default `~/.claude/skills/gstack/browse/` daemon. Use the existing
gstack browse skill in its full-fidelity mode.

## Phase 3: Update the cache

On success, write the winning method to `~/.jjstack/browse-routes.json`
under the resolved host. On failure of all backends, leave the cache
unchanged (do not record failures - the host may just be down).

## Phase 4: Return the result

Return the page content (markdown-converted if HTML) and a small
metadata block:

```
[browse] host=github.com method=curl status=200 size=14823 cached=true
```

The metadata helps the caller know whether they hit cache and what
backend won.

## Important rules

- **Algorithm first, inference last.** This skill is exact-match
  routing + ordered fallback. No LLM, no vector similarity. The cache
  is a json file.
- **Validation matters.** A 200 OK that contains "Just a moment..."
  is a failure. The validator catches the silent-success-actually-
  blocked case.
- **Never write to gstack's browse daemon code.** This skill wraps
  the daemon, it does not edit it.
- **Failures do not poison the cache.** If a domain returns 500 from
  curl today, do not lock it to Playwright forever. Only successes
  update the cache.
- **One backend per request.** Do not try all four in parallel - the
  ordering exists to save cost on the cheap-and-common case.
- **Refresh the cache entry on success.** Update the `updated`
  timestamp so old entries can be expired by a future `/groom routes`
  pass if the chain shifts.
