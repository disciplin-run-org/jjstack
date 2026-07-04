---
name: browse
version: 0.2.0
description: |
  Adaptive web-page reader AND page screenshotter: try the fastest
  backend first, fall back to slower-but-more-capable backends on
  failure, learn the winning method per domain, cache it in
  browse-routes.json. Read backends in order: curl (fastest, no JS, no
  auth), cookied headless chrome (JS + your session cookies),
  claude-in-chrome MCP (real browser tab, anti-bot stealth), Playwright
  via gstack browse daemon (full automation, slowest). Screenshot mode
  renders the page to a PNG that Claude Reads and visually analyzes —
  works in worker sessions with no chrome MCP.
  Trigger on: "browse", "read this page", "fetch the URL", "scrape this",
  "get the page content", "load this URL", "what's on this page",
  "read the docs at <url>", "screenshot <url>", "visual check <url>",
  "what does the page look like", "browse --screenshot".
  Do NOT trigger for: file reads (use Read), git operations, or anything
  that does not start from a URL. For browser-driven QA testing of a
  deployed app (clicking, asserting, multi-step flows), use /qa,
  /qa-only, or /browse-daemon-direct. This skill READS and LOOKS AT
  pages; QA skills TEST them.
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

## Screenshot mode

When the ask is visual — "screenshot <url>", "visual check <url>",
"does the UI look right", pixel-verifying a UI change (qa-build-loop
Rule 11) — render the page to a PNG and **Read the PNG** (Claude
analyzes images natively). Backend ladder, cheapest first:

### Backend S1: headless chrome CLI (no MCP, no daemon — works in any worker session)

```bash
google-chrome --headless=new --disable-gpu --window-size=1440,900 \
  --screenshot=<scratchpad>/shot-<host>-<ts>.png \
  --virtual-time-budget=8000 "<URL>"
```

- `--virtual-time-budget=8000` lets SPAs finish rendering before capture.
- `--window-size` sets the viewport; use `1440,900` default, or the size
  the check calls for (e.g. `390,844` for mobile).
- Binary fallback order: `google-chrome`, `google-chrome-stable`,
  `chromium`.
- Then `Read` the PNG and compare what you SEE against the requirement.
  State the comparison explicitly (e.g. "sidebar reads 'Iris-QA' mixed
  case ✓; panels fill viewport ✗ — 60vh cap still visible").
- Full-page height: add `--window-size=1440,<tall>` (e.g. 3000) when the
  check concerns below-the-fold content.

Proven live 2026-07-04: one command captured the running iris-qa SPA
(localhost:8004) and the brand-casing fix was verifiable in the image.

### Backend S2: Playwright via gstack browse daemon

When S1's capture is wrong (page needs real cookies, fights headless, or
needs element-level shots / precise measurements): the gstack browse
daemon's Playwright can screenshot and also MEASURE (bounding boxes,
computed styles). Use for numbers, S1 for looks.

### Backend S3: claude-in-chrome MCP

Interactive sessions only (workers usually have it barred):
`tabs_create_mcp` + the computer/screenshot tools. Never a dependency in
unattended loops.

Cache note: screenshot routing reuses `browse-routes.json` hosts — a
host cached as `playwright` for reading should start at S2 for shots.

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
