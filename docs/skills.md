# jjstack — a walkthrough

This is not a reference. The README is the reference. This is a single
running path from "I just installed it" to "I shipped something."
Follow it top to bottom and you will have exercised every skill worth
knowing in roughly its natural position.

> **The running example.** You are building a tiny standalone MCP
> server that reports system uptime over HTTP. Three tools: `uptime`,
> `load_average`, `meminfo`. Dockerized. A small config page for the
> refresh interval. At the end you publish it to your own GitHub
> account and wire it into your own `~/.mcp.json`. No monorepo
> assumptions, no ecosystem dependencies, no special setup. 2-3 hours
> end to end if you type along.

## Who this is for

- A developer who just ran `./setup` and wants to know what to type
  first.
- A jjstack user who has been living on five or six skills and wants
  to discover the ones they have been missing.

## Who this is NOT for

- One-off chat questions ("what's the difference between X and Y") —
  jjstack has heavy ceremony that is wasted on trivia.
- Throwaway prototypes you will not ship — the quality loop and
  review gates are worth their tokens only when the code actually
  matters.
- Exploratory research where debate and pushback are the point.
  jjstack is opinionated. If you want an open conversation, skip
  jjstack for that session.

## Table of contents

- [Prep — install and verify](#prep--install-and-verify)
- [Phase 1 — Think](#phase-1--think)
- [Phase 2 — Stage](#phase-2--stage) *(coming in Pass 2)*
- [Phase 3 — Build](#phase-3--build) *(coming in Pass 2)*
- [Phase 4 — Test](#phase-4--test) *(coming in Pass 2)*
- [Phase 5 — Review](#phase-5--review) *(coming in Pass 2)*
- [Phase 6 — Ship](#phase-6--ship)
- [Phase 7 — Reflect](#phase-7--reflect)
- [Meta — extending jjstack](#meta--extending-jjstack) *(coming in Pass 3)*
- [Troubleshooting](#troubleshooting) *(coming in Pass 3)*
- [Going deeper](#going-deeper) *(coming in Pass 3)*

---

## Prep — install and verify

### Install jjstack

```bash
git clone https://github.com/JesperJurcenoks/jjstack.git ~/.claude/skills/jjstack
cd ~/.claude/skills/jjstack
./setup
```

`./setup` does a lot:

- Installs gstack (mandatory dependency) if not already present.
- Clones three security-review reference repos (Anthropic, Sentry,
  OWASP) so `/security-review` has current methodology to lean on.
- Symlinks ~50 skills into `~/.claude/skills/`. Wrapper skills replace
  gstack's versions transparently — you keep the same command names,
  you get jjstack's enhancements.
- Registers four hooks in `~/.claude/settings.json` (more below).
- Creates `~/.jjstack/` as state dir (update snooze, command-failure
  log, retry tracking).
- Optionally prompts to install the Context7 MCP server. **Say yes.**
  `/smart-context7` depends on it and you will use it in Phase 3.

### Verify the statusline

jjstack installs a custom statusline that shows:

```
Opus 4.7 ·high | jjstack | main clean | context  12% | usage  31%
```

Left to right: model, effort level, current folder, git branch + state,
context-window usage percent, and either 5-hour rate-limit usage
(OAuth / Max / Pro users) or session dollar spend (API-key users) —
the statusline auto-detects which of the two you are.

The effort badge is color-coded: dim for `auto` (the default), green
for `low`, yellow for `medium`, red for `high`, magenta for `xhigh`.
To pin a specific level so the badge shows in color, edit
`~/.claude/settings.json`:

```bash
jq '.effortLevel = "high"' ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json
```

If the statusline does not render, restart your terminal and check
that `~/.claude/settings.json` has a `statusLine` entry pointing at
`jjstack/bin/statusline.sh`. If you already had a different statusline
configured, `./setup` will have asked whether to overwrite — default
N preserves yours.

### Context7

`./setup` will have prompted you. If you said no, run it again — the
prompt is idempotent. Context7 is how `/smart-context7` fetches
library docs for you on demand. You want it.

### Sanity check

```
/jjstack-repair
```

This confirms all jjstack symlinks are intact. If gstack upgraded
after you ran `./setup`, gstack may have replaced a jjstack wrapper
with its own version — `/jjstack-repair` puts things back.

### Browser and deploy setup (you will need these later)

```
/setup-browser-cookies
/setup-deploy
```

`/setup-browser-cookies` imports cookies from your real Chromium so
`/qa` (Phase 4) can QA authenticated pages. `/setup-deploy` detects
your deploy platform (Fly / Render / Vercel / Netlify / Heroku /
GitHub Actions / custom) and writes the config `/land-and-deploy`
(Phase 6) needs. Do both now so Phase 4 and Phase 6 do not stall on
setup.

### Hooks that run silently

Four hooks got registered. You do not interact with them directly but
should know they are there.

- **auto-approve-safe** — every shell command you would otherwise get
  prompted on runs through a Haiku risk classifier first. LOW-risk
  commands auto-approve; MEDIUM and HIGH still prompt. Read-only
  tools always auto-approve. Fail-closed: if the API is down, only a
  conservative allow-list runs without a prompt.
- **injection-guard** — every `Write` or `Edit` to a `.md` file is
  scanned for known prompt-injection patterns (fake system-reminder
  tags, role-reprogramming phrasing, unicode tag steganography). It
  blocks the write on match; the block message explains how to
  rephrase. If you hit it writing legitimate content — for example,
  documenting the hook itself — the fix is usually to wrap the
  triggering phrase in a code fence.
- **error-detector** — every failed Bash command gets appended to
  `~/.jjstack/command-failures.jsonl`. You do not need to look at
  that file right now. Phase 7 does.
- **mcp-reconnect** — if an MCP server drops mid-session, this hook
  tries up to three reconnects before escalating to you.

---

## Phase 1 — Think

Before code, before plans, think. jjstack loads two frameworks at the
start of this phase so every subsequent question has a vocabulary to
answer in.

### Step 1 — `/dev-philosophy`

**What it does.** Loads the 11-layer development framework: Vision →
Mission → SMAC → OKR → Strategy → KPIs → Spec → Skills → Code →
Deploy → Learn.

**What you type.**
```
/dev-philosophy
```

**What you'll see.** A short recap of each layer and which layer your
current work sits at. For our uptime MCP server, you are at the Spec
and Skills layers — vision-through-strategy is already defined
(personal tooling, one-off utility, no OKR).

**Why this skill here.** Grounds the rest of the session. Planning
skills downstream know which layer they should be operating at. Skip
it only if you are certain you know where you are; load it if you are
new to jjstack.

### Step 2 — `/kano-model`

**What it does.** Loads the 10-level extended Kano model ("steam
train"): Security and Legal through Single Customer and Show Horse.
Each feature gets a kano level that dictates test depth and quality
tolerance.

**What you type.**
```
/kano-model
```

**What you'll see.** Level descriptions plus a prompt to classify the
current work. The uptime MCP server is mostly level 3-4 (Must-be /
Performance): basic correctness matters; no one cares if it's
delightful.

**Why this skill here.** Calibrates every skill downstream that cares
about quality. `/qa` at level 3 is a different animal from `/qa` at
level 9. Setting the level now means later skills inherit it instead
of asking you.

### Step 3 — `/office-hours`

**What it does.** A YC-style partner sits down with you and pokes at
the premise. Before you plan, before you write code, before you ask
"how" — answer "what are you actually building?"

**What you type.**
```
/office-hours
```

**What you'll see.** Questions, one at a time. "What's the pain?"
"What would the demo look like?" "What's the 10-star version hiding
inside this request?" Ends with a design doc at
`your-repo/jjstack/office-hours-YYYY-MM-DD.md`.

**Why this skill here.** Kills scope creep before it happens. For the
uptime MCP server you will discover you only need three tools, not
twelve. The design doc from this step is the input to every planning
skill that follows.

**Gotcha.** It WILL push back. When it asks "why would anyone use
this over `top`?", answer honestly. If you cannot, rethink the
project. That is the point.

### Step 4 — `/plan-ceo-review`

**What it does.** Strategic review. Does this project justify itself
against your goals? Iterates the critique to 10/10.

**What you type.**
```
/plan-ceo-review
```

**What you'll see.** A series of adversarial questions ("is this the
highest-leverage thing you could be building right now?") and an
artifact at `your-repo/jjstack/plan-ceo-review-YYYY-MM-DD.md`. The
quality loop runs until the score hits 10/10 or you explicitly lower
the threshold.

**Why this skill here.** If the project fails the CEO review, kill it
now. Cheaper than after you have written 500 lines. For the uptime
MCP server this will be quick — it passes because it is small,
specific, and eliminates a recurring friction.

### Step 5 — `/product-manager-review`

**What it does.** Adversarial product-management pass across eight
dimensions. Kills features, tightens scope, checks OKR alignment
(even for a one-off, the question "which outcome does this serve?"
is useful).

**What you type.**
```
/product-manager-review
```

**What you'll see.** A kill-list for features that do not pull their
weight. For the uptime MCP server the kill list is probably the
config page ("do you actually need it?"). The right answer depends
on whether you will tune the interval more than twice ever.

**Why this skill here.** Planning and engineering reviews get you to
a good plan for what you chose to build. PM review asks whether you
chose the right thing to build. Run it before you commit to
implementation.

### Step 6 — `/plan-eng-review`

**What it does.** Architecture review. What's the runtime? What's the
data flow? What are the failure modes? Iterates to 10/10.

**What you type.**
```
/plan-eng-review
```

**What you'll see.** Architecture critique, stack selection feedback
("FastMCP is right for streamable HTTP; streamable is the current
default"), artifact at
`your-repo/jjstack/plan-eng-review-YYYY-MM-DD.md`.

**Why this skill here.** The CEO review said yes; now answer "how."
The quality loop catches "oh we forgot about X" before you hit X
mid-implementation.

### Step 7 — `/plan-devex-review`

**What it does.** Developer-experience review. For an MCP server, the
tool schema IS the public API — this is where you get it right
before users (or your future self) hate you.

**What you type.**
```
/plan-devex-review
```

**What you'll see.** Persona walk-throughs ("I am a Claude Code user
who just installed this MCP. What is my first call?"), friction
audit, comparison against similar MCP servers in the wild.

**Why this skill here.** The tool names (`uptime`, `load_average`,
`meminfo`) and their return shapes are the contract. Getting them
wrong means users will wrap them in ugly helper functions forever.
Get them right once.

### Step 8 — `/plan-design-review`

**What it does.** Design plan critique. For our tiny config page
(refresh interval tuning) this is not big, but the muscle still runs
— even one input field benefits from a design pass.

**What you type.**
```
/plan-design-review
```

**What you'll see.** Questions about layout, state flow, edge cases
("what does the page show if the backend is down?"), artifact at
`your-repo/jjstack/plan-design-review-YYYY-MM-DD.md`.

**Why this skill here.** The config page is small enough that
skipping design review is tempting. Don't. Even one input field has
three states (unset, valid, invalid) and zero of them should look
broken.

### Step 9 — `/design-consultation`

**What it does.** Builds a mini design system for the project:
palette, typography, spacing. The artifact lives in your repo so
every subsequent UI change lands consistently.

**What you type.**
```
/design-consultation
```

**What you'll see.** A back-and-forth that ends with
`your-repo/jjstack/design-system.md` — Nordic-minimalism-flavored by
default (opinionated; override if you want something else).

**Why this skill here.** Even for a one-page config UI, having the
system file pays off the second time you touch the page. Without
it, every CSS tweak becomes a thread.

### Step 10 — `/design-shotgun`

**What it does.** Generates multiple AI design variants side by side
for you to compare. "Show me three" rather than "build me one."

**What you type.**
```
/design-shotgun
```

**What you'll see.** Three HTML mockups in
`your-repo/jjstack/design-shotgun-YYYY-MM-DD/`. Open them side by
side and pick.

**Why this skill here.** Cheap. AI generates three variants in the
time it takes to decide between two. Structured feedback at this
stage beats "I'll know it when I see it" later.

### Step 11 — `/design-html`

**What it does.** Finalizes the chosen design into production-quality
Pretext-native HTML/CSS. Text actually reflows, heights compute
correctly, no framework overhead.

**What you type.**
```
/design-html
```

**What you'll see.** `your-repo/config/index.html` + `style.css`,
30KB total, zero dependencies. The config page is now buildable.

**Why this skill here.** The ship point for design. After this, the
design feeds the build phase — no more changes without going back to
`/design-consultation`.

At this point you have: a project premise (vetted), a kill-list (PM),
an architecture (eng review), a contract (devex), a design plan
(design review + design system), and final HTML. No code yet. That
is correct — the Think phase is for decisions that become expensive
to unmake once code exists.

---

## Phase 2 — Stage

*Full walkthrough lands in Pass 2. Preview: `/work-order` to draft the
implementation task in Context/Deliverables/Verify/Done-when shape
(HARD-GATE enforced), `/state-doc` to create STATE.md at repo root,
`/worktrees` to branch in isolation, `/lean` to cap tool-call budget
if cost matters, `/checkpoint` before the big build.*

## Phase 3 — Build

*Pass 2. Skills: `/github-setup`, `/mcp-server`, `/python-coder`,
`/jj-code`, `/smart-context7`.*

## Phase 4 — Test

*Pass 2. Skills: `/unit-test-builder`, `/verify-before-done`, `/jj-qa`,
`/qa`, `/qa-only`, `/qa-review`, `/benchmark`.*

## Phase 5 — Review

*Pass 2. Skills: `/two-stage-review`, `/smart-review`, `/review`,
`/security-review`, `/cso`, `/codex`, `/receiving-code-review`.*

---

## Phase 6 — Ship

This is a preview of the ship phase. Full walkthrough comes together
in Pass 2 once the preceding phases land. Here is the shape.

### Step 36 — `/careful`

**What it does.** Enables destructive-command warnings:
`rm -rf`, `git reset --hard`, `git push --force`, `DROP TABLE`,
`kubectl delete` all prompt before running even if they would
otherwise auto-approve.

**What you type.**
```
/careful
```

**What you'll see.** A confirmation that careful mode is active for
the rest of the session. Every risky command now asks explicitly.

**Why this skill here.** Ship means prod-adjacent operations. Prod
mistakes are expensive. The cost of one extra `y` keystroke per
destructive command is negligible; the cost of one wrong
`git push --force` on main is not.

### Step 37 — `/ship`

**What it does.** Creates the PR with jjstack conventions: repo
output captured, DNA injected into the description, README
maintenance run, CI targets documented. Operates from your
`/worktrees` branch (Phase 2), not main.

**What you type.**
```
/ship
```

**What you'll see.** The PR URL. The description includes
Context / Deliverables / Verify sections pulled from the earlier
work order (Phase 2). The ship artifact lands in
`your-repo/jjstack/ship-<sha>.md` for the next release.

**Why this skill here.** The PR description is the handoff contract
to reviewers and future you. `/ship` writes it once, consistently,
so you do not leave "figure it out from the diff" PRs behind.

### Step 38 — `/land-and-deploy`

**What it does.** Merges the PR, waits for CI, watches the deploy
pipeline, runs a post-deploy canary.

**What you type.**
```
/land-and-deploy
```

**What you'll see.** A live status line — CI green, deploy rolling,
health checks passing. If anything fails, stops and tells you where.

**Why this skill here.** Merge + wait + verify is a three-step
sequence that is easy to short-circuit ("I'll check it later" means
"I'll find out about the regression from a user"). `/land-and-deploy`
blocks until the deploy is actually green in prod.

### Step 39 — `/canary`

**What it does.** Post-deploy anomaly watch. Screenshots, console
errors, performance regressions compared against pre-deploy baseline.

**What you type.**
```
/canary
```

**What you'll see.** A monitor that reports on anomalies as they
occur. Console error spikes, Core Web Vitals regressions, 500
responses — each gets a notification with evidence.

**Why this skill here.** `/land-and-deploy` confirms the deploy
completed; `/canary` confirms the deploy still works five minutes
later. Many regressions only surface under real traffic.

### Step 40 — `/document-release`

**What it does.** Post-ship documentation update. README refreshed
if commands changed; CHANGELOG entry added; any relevant
configuration docs synced.

**What you type.**
```
/document-release
```

**What you'll see.** A diff of docs updates. Review and commit.

**Why this skill here.** Docs lie by default — every ship that
doesn't update them drifts further from reality. `/document-release`
runs immediately after ship so the window for drift is minutes, not
months.

---

## Phase 7 — Reflect

Every ship ends with a brief reflect phase. Three skills, one
signal check. Skip none of them.

### Step 41 — `/retro`

**What it does.** Retrospective. What worked, what didn't, what to
change. Writes to the repo with DNA injection so the artifact sounds
like you.

**What you type.**
```
/retro
```

**What you'll see.** A structured retro doc at
`your-repo/jjstack/retro-<date>.md`.

**Why this skill here.** The cost of a retro is small; the cost of
repeating the same mistake next sprint is not.

### Step 42 — `/investigate`

**What it does.** Root-cause analysis. Only run if prod hit an issue
— otherwise skip.

**What you type.**
```
/investigate
```

**What you'll see.** A disciplined trace: symptom, evidence,
hypothesis, proof, fix. Artifact in repo.

**Why this skill here.** Prod issues that get "I fixed it" without
a root-cause doc come back. `/investigate` forces the root-cause
question before the fix ships.

### Step 43 — `/learn`

**What it does.** Manages project learnings. Prune stale ones,
export the useful ones, surface patterns.

**What you type.**
```
/learn
```

**What you'll see.** Your current learnings plus pruning
suggestions.

**Why this skill here.** STATE.md has a Learnings section; this is
where those graduate out once the branch merges.

### Step 44 — Check the command-failure log

Not a slash command — just a shell one-liner:

```bash
jq -r '.command' ~/.jjstack/command-failures.jsonl \
  | sort | uniq -c | sort -rn | head
```

This shows the top commands you have been running that failed. If
any pattern appears three or more times across your sessions, it is
a candidate for promotion to CLAUDE.md per
`references/memory-promotion.md`. Either you have a mental model gap
worth codifying, or you have a tooling gap worth fixing.

---

*Pass 2 (Stage / Build / Test / Review) and Pass 3 (Meta +
Troubleshooting + Going deeper) land next. This document is being
written incrementally on branch `docs/tutorial`.*
