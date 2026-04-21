# jjstack — a walkthrough

One running session. One project. All the skills you actually type.

**The project**: a tiny standalone MCP server that reports system status
(`uptime`, `load_average`, `meminfo`) over HTTP. You publish it to your
own GitHub and wire it into your own `~/.mcp.json`. 2-3 hours end to end.

## Who this is for

A developer who ran `./setup` and wants to know what to type first, or
an existing jjstack user who's been living on six skills and suspects
they're missing some. If you're looking for a reference, read the
README — this is a path.

## Prep (5 minutes)

```bash
git clone https://github.com/JesperJurcenoks/jjstack.git ~/.claude/skills/jjstack
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
        RECOMMENDATION: FastMCP + streamable HTTP + Docker. Three tools,
        no config UI (you'll tune the refresh interval twice ever).
        → your-repo/jjstack/office-hours-2026-04-21.md
```

```
You:    Agreed on three tools, skip the config page. Next.
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
You:    /work-order for the implementation
Claude: [drafts Context / Deliverables / Verify / Done-when]
        [HARD-GATE refuses to continue until all four sections present]
        → work-order-impl-001.md
```

```
You:    Approve plan. Exit plan mode.
Claude: [creates STATE.md at repo root via /state-doc]
        [creates worktree ../uptime-mcp-wt/build-001 via /worktrees]
```

```
You:    /mcp-server
Claude: [scaffolds FastMCP + streamable HTTP + Dockerfile +
         docker-compose + /healthz + first tool: uptime()]
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
You:    /qa http://localhost:8003
Claude: [browser QA — imports cookies via /setup-browser-cookies]
        [hits /healthz, calls each tool, cleans up snapshot state after]
        FOUND: meminfo() 500s when /proc/meminfo has trailing whitespace
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
Claude: Stage 1 spec compliance vs work-order-impl-001.md:
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
You:    /careful
        /ship
Claude: [PR via /github-setup-created repo on your GitHub account]
        → github.com/you/uptime-mcp/pull/1
        Description: Context / Deliverables / Verify / Security notes
                     pulled from the work order + security review.
        Tests: 20. CI configured via your semver-auto-bump Action.
```

```
You:    /land-and-deploy
Claude: [/smart-review fired automatically, no new blockers]
        [merges; CI green in 2m]
        [deploys to your configured platform via /setup-deploy]
        [/canary runs for 5m — no console errors, no regressions]
        Live at https://uptime-mcp.your-domain.com/mcp. 200 healthy.
```

```
You:    Add it to ~/.mcp.json so Claude Code can call it.
Claude: [edits ~/.mcp.json]
          "uptime-mcp": { "type": "http",
                          "url": "https://uptime-mcp.your-domain.com/mcp" }
        [the injection-guard hook scans the write — clean]
```

```
You:    /retro
Claude: [writes retro — what worked, what didn't, what to change]
        → your-repo/jjstack/retro-2026-04-21.md
          Worked: devex review killed a redundant tool before it shipped.
          Didn't: security-review found a bigger issue than expected —
                  consider running it earlier next time, before /ship.
          Change: add security pass between verify and two-stage-review.
```

```
You:    $ jq -r '.command' ~/.jjstack/command-failures.jsonl \
          | sort | uniq -c | sort -rn | head
        3 docker compose up --build
        1 pytest tests/test_uptime.py::test_since_param
```

`docker compose up --build` failing three times is a recurrence. The
fix (add Docker layer caching config or increase build resources) is a
candidate for promotion to CLAUDE.md per
`references/memory-promotion.md`.

```
You:    /learn
Claude: [shows current STATE.md Learnings + memory entries]
        [you promote the docker-build note to CLAUDE.md]
```

---

## What we didn't exercise

Skills you'll reach for when the context calls for them but the uptime
MCP didn't need:

- **UI-heavy work** → `/plan-design-review`, `/design-consultation`,
  `/design-shotgun`, `/design-html`. Skipped here because a
  two-tool MCP has no UI.
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
