# jjstack — a walkthrough

One running session. One project. All the skills you actually type.

**The project**: a tiny standalone MCP server that reports system status
(`uptime`, `meminfo`) over HTTP, plus a dashboard page that graphs uptime
history. You publish it to your own GitHub and wire it into your own
`~/.mcp.json`. 2-3 hours end to end.

## Who this is for

A developer who ran `./setup` and wants to know what to type first, or
an existing jjstack user who's been living on six skills and suspects
they're missing some. If you're looking for a reference, read the
README — this is a path.

## Prep (5 minutes)

```bash
git clone https://github.com/Disciplin-run-org/jjstack.git ~/.claude/skills/jjstack
cd ~/.claude/skills/jjstack && ./setup
```

`./setup` symlinks the skills, registers four hooks (auto-approve
risk classifier, prompt-injection guard on `.md` writes, Bash error
detector, MCP auto-reconnect), and prompts you to install the Context7
MCP server. Say yes to Context7.

Your statusline now shows `model · effort | folder | branch | context%
| usage% or $spend`. The effort badge is dim for `auto`; to pin it and
get a colored badge:

```bash
jq '.effortLevel = "high"' ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json
```

Before you start, run these once — they configure skills you'll need
later:

```
/setup-browser-cookies
/setup-deploy
```

Now the session begins.

---

## The session

```
You:    I want a tiny MCP server that reports system status over HTTP.
        I keep typing `uptime` + `free -h` in debug sessions and want
        Claude to just ask.
You:    /office-hours
```

Claude pushes back on the framing.

```
Claude: You said "uptime MCP." You described a system-status MCP. The
        distinction matters — with the wider name you'll keep adding
        tools (`disk`, `iostat`, `who`). Pick three now, ship, then
        add the fourth only if you reach for it.
        [5 questions; 3 implementation approaches with effort estimates]
        One thing hidden in your answers: you don't just want a snapshot
        of right-now — you want to see whether the server was struggling
        at 3am. That's a history feature, and it deserves a dashboard
        page, not just another tool call. The graph IS the product.
        RECOMMENDATION: FastMCP + streamable HTTP + Docker. Three system
        tools + in-memory ring buffer for uptime history + dashboard
        page at `/` that graphs the last 24h.
        → your-repo/jjstack/office-hours-2026-04-21.md
```

```
You:    Agreed — tools plus the dashboard. Next.
You:    /plan-ceo-review
Claude: [10-section strategic pass, iterates to 10/10]
        Verdict: ships. Small scope, real pain, no OKR ambiguity.
        → plan-ceo-review-2026-04-21.md
```

```
You:    /plan-eng-review
Claude: [architecture: FastMCP 0.3+, streamable HTTP, Docker, no DB]
        [ASCII diagram: client → /mcp POST → tool dispatcher → /proc reads]
        [failure modes: /proc unreadable, parse edge cases, timeout]
        [10/10 after 2 iterations]
        Recommend following up with /plan-devex-review — this is a
        developer-facing service (MCP tool schemas ARE the public API)
        and eng-review covers internals, not the outward surface.
```

```
You:    /plan-devex-review
Claude: The tool schema IS the public API. Scrutinizing:
          uptime()        → {seconds: int, human: str, loadavg: [f,f,f]}
          load_average()  → duplicates uptime's loadavg. Kill this tool.
          meminfo()       → {total_kb, free_kb, available_kb, percent_used}
        Recommend dropping load_average. Two tools, not three.
        Also: add `since` param to uptime for "uptime since last boot vs
        since process start."
```

```
You:    Agreed — drop load_average. Keep meminfo. Add `since`.
```

```
You:    /plan-design-review
Claude: The dashboard is narrow product surface — one page, one graph —
        but every state needs a plan:
          - empty state (server just started, no history yet)
          - error state (backend unreachable, stale data)
          - degraded state (one sample missing, gap in the line)
          - mobile (uptime ops from a phone during an incident)
        Also: time axis resolution (seconds? minutes? 5-min buckets?)
        Bucket at 1-min — matches the 60s sampler, keeps the SVG under
        1440 points over 24h.
        [iterates to 10/10]
```

```
You:    /design-consultation
Claude: [builds a mini design system for the dashboard]
        Palette: background neutral, uptime line single accent color,
        degraded-sample markers in a warning color. Two typefaces max:
        system UI for chrome, mono for numeric labels. 8/16/24 spacing
        scale.
        → your-repo/jjstack/design-system.md
```

```
You:    /design-shotgun
Claude: [three variants]
        → variant-a: single wide sparkline, current uptime as big number
        → variant-b: area chart with 1-hr gridlines, legend below
        → variant-c: calendar heatmap (each cell = 1 hour)
        Variant A wins — matches "glance, not analyze" usage.
```

```
You:    /design-html
Claude: [finalizes Pretext-native HTML + CSS + inline SVG chart]
        → your-repo/dashboard/index.html  (18 KB)
        → your-repo/dashboard/style.css   (4 KB)
        No JS frameworks, no chart libraries — SVG built from /history
        JSON with ~40 lines of inline script. Text reflows, heights
        compute correctly on resize.
```

```
You:    Approve plan. Exit plan mode.
```

```
You:    /mcp-server
Claude: [scaffolds FastMCP + streamable HTTP + Dockerfile +
         docker-compose + /healthz + first tool: uptime()]
        [also: GET / serves the dashboard HTML from /design-html's output,
         GET /history returns the ring-buffer samples as JSON, and a
         background thread writes a sample every 60s into an in-memory
         1440-slot ring buffer — 24h of history per process]
        [/smart-context7 fires automatically to fetch FastMCP 0.3 API —
         you didn't type it; it runs when the agent needs versioned docs]
```

```
You:    /python-coder add the meminfo tool
Claude: [writes tools/meminfo.py parsing /proc/meminfo]
        [runs through black / isort / ruff / mypy; all clean]
        [matches project line length 88, existing conventions]
```

```
You:    /unit-test-builder
Claude: [TDD suite: 19 tests across both tools]
        - boundary: /proc/meminfo missing fields, reordered lines
        - boundary: uptime kernel 2.x vs 5.x format differences
        - mock: system calls, fixed clocks for reproducibility
        - mutation: kill off-by-one in percent calculation
        [19/19 pass]
```

```
You:    /verify-before-done
Claude: [HARD-GATE: refuses "done" without captured evidence]
        $ docker compose up --build  → healthy on port 8003
        $ curl /healthz               → {"ok": true, "tools": 2}
        $ pytest                      → 19 passed in 0.4s
        $ ruff check                  → no issues
        $ mypy .                      → no issues
        Verified. You may declare done.
```

```
You:    /heal
Claude: [notices docker-compose.yml; generates per-service debug scripts]
        → debug/mcp-server.sh      (health probe, logs, restart)
        → debug/run.sh             (master orchestrator: binary-search
                                    fault isolation across services)
        Now when something goes sideways in prod, you do not start from
        zero — the scaffolding is already there.
```

```
You:    /qa http://localhost:8003
Claude: [browser QA — imports cookies via /setup-browser-cookies]
        [loads /, confirms the graph renders, scrubs for 5 min to watch
         live samples append, resizes to mobile width, confirms /history
         endpoint, calls each tool, cleans up snapshot state after]
        FOUND: meminfo() 500s when /proc/meminfo has trailing whitespace
        FOUND: dashboard Y-axis clips labels when uptime stays > 99.5%
               (tick labels collide with the line)
        FOUND: empty state reads "undefined hours" before the first sample
               lands — should say "waiting for first sample…"
        [writes bug report to your-repo/jjstack/qa-2026-04-21.md]
```

```
You:    Fix the whitespace bug.
You:    /verify-before-done
Claude: [re-runs pytest — adds regression test first per TDD]
        PASS 20/20. Bug confirmed fixed.
```

```
You:    /two-stage-review
Claude: Stage 1 spec compliance vs the approved eng-review plan:
          deliverables [x] uptime [x] meminfo [x] /healthz [x] Docker
          scope creep: none. PASS.
        Stage 2 code quality (fresh subagent):
          [HIGH] tools/uptime.py:34 swallows ConnectionError silently
          [MEDIUM] missing docstring on public _parse_meminfo
          [LOW] 1 style nit
        [you fix HIGH and MEDIUM; LOW is discretionary]
        Re-run Stage 2: PASS.
```

```
You:    /security-review
Claude: [loads Anthropic + Sentry + OWASP + jjstack MCP-specific CWE]
        [10-phase assessment: STRIDE summary, 14+ secret patterns,
         insecure defaults, MCP-specific risks]
        Findings:
          [CRITICAL] /proc reads expose container hostnames to anyone
            hitting /mcp — no auth. Bind to localhost or add bearer.
          [HIGH] meminfo returns RAM totals — trivial fingerprinting
            of container size. Consider generalizing.
          [LOW x3] header hardening, version disclosure in /healthz
        [you add bearer-token auth; HIGH/LOW accepted as known trade-offs]
        Re-run: Critical resolved. Ship.
```

```
You:    /ship
Claude: [/smart-review fires automatically before the PR is opened —
         no blockers]
        [creates PR on your GitHub repo]
        → github.com/you/uptime-mcp/pull/1
        Description: Context / Deliverables / Verify / Security notes
                     pulled from the planning docs and security review.
        Tests: 20. CI configured via your semver-auto-bump Action.
```

```
You:    Add it to ~/.mcp.json so Claude Code can call it.
Claude: [edits ~/.mcp.json]
          "uptime-mcp": { "type": "http",
                          "url": "https://uptime-mcp.your-domain.com/mcp" }
        [the injection-guard hook scans the write — clean]
```

---

## What we didn't exercise

Skills you'll reach for when the context calls for them but this
project didn't need:

- **Structured delegation** → `/work-order` formalizes hand-offs to
  sub-agents or PR bodies into Context / Deliverables / Verify /
  Done-when shape. Useful when delegating; unnecessary when you're
  driving the session yourself.
- **Session state and branch isolation** → `/state-doc` keeps a live
  `STATE.md` at repo root that survives `/clear` and session
  restarts; `/worktrees` creates isolated worktrees when you need to
  run multiple branches in parallel. Both pay off on multi-day
  efforts; overkill for a two-hour build.
- **Post-ship flow** → `/careful` enables destructive-command
  warnings when touching prod; `/land-and-deploy` merges + waits for
  CI + deploys + runs canary; `/canary` does standalone post-deploy
  anomaly watch; `/retro` captures what worked and what didn't;
  `/learn` manages accumulated project learnings. Pull them in on
  real production ships.
- **Philosophy loaders** → `/dev-philosophy`, `/kano-model`. Load
  either when you want the frameworks explicit in the session; plan
  skills already reference them implicitly.
- **Adversarial framing** → `/product-manager-review` kills features
  harder than `/plan-ceo-review` does, `/codex` gives you a second
  opinion from an entirely different model. Pull them in on calls
  that need sharper teeth.
- **Cost control** → `/lean [20|50|100]` for bulk work (QA loops,
  batch generation) — caps the tool-call budget and enforces
  minimum-turn rules.
- **Safety modes** → `/freeze` to restrict edits to one directory,
  `/guard` for full safety mode.
- **Extending jjstack** → `/writing-skills` documents the meta-skill
  for authoring your own.
- **Variants and alternates** → `/qa-only` for report-only QA,
  `/qa-review` to audit the tests themselves, `/cso` for a
  security audit with repo artifacts instead of inline findings,
  `/benchmark` for perf regression detection.
- **When the stack breaks** → `/jjstack-repair` fixes symlinks
  after a gstack upgrade; `/gstack-upgrade` updates the base.

## Auto-trigger skills (you don't type these)

- `/smart-review` — fires before PR creation, runs the Anthropic
  code-review plugin.
- `/smart-simplify` — fires after significant code changes, runs the
  code-simplifier plugin.
- `/smart-context7` — fires when library-version accuracy matters,
  calls Context7 for current docs.
- `/jj-qa` — QA philosophy reference; loaded automatically by `/qa`.

## Going deeper

- `references/hard-gate-convention.md` — why some gates are mechanical
- `references/memory-promotion.md` — recurring pattern -> permanent rule
- `references/quality-loop.md` — the 10/10 iteration mechanic
- `references/coding-dna.md` — the voice planning skills inject
- Install the full superpowers methodology in parallel:
  `/plugin install superpowers@claude-plugins-official`
