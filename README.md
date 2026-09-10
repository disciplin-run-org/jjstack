<h1 align="center">jjstack</h1>

<p align="center">
  <strong>Claude Code, with the lessons baked in.</strong><br>
  A curated UX layer on top of <a href="https://github.com/garrytan/gstack">gstack</a> that turns hard-won product knowledge into reusable skills, references, and quality floors.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.12.1-blue" alt="version">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
  <img src="https://img.shields.io/badge/Claude%20Code-skills-orange" alt="claude code">
  <img src="https://img.shields.io/badge/skills-42-purple" alt="42 skills">
</p>

---

## Why jjstack

After two decades of shipping security and AI products, I noticed every team
relearns the same lessons the hard way:

- "Don't ship without an OKR for it."
- "Test the corner cases at Kano level 1, not just the happy path."
- "Production truth beats staging confidence beats local hope."
- "The PM who kills 10 features did more than the PM who shipped 15."

These are not opinions — they're scars. **jjstack encodes them as skills,
references, and quality gates so every Claude Code session inherits them
automatically.** No more re-explaining your testing standards in every
prompt. No more 8/10 reviews shipping as good enough.

jjstack does not replace gstack — it stands on its shoulders. Same command
names you already know (`/review`, `/qa`, `/ship`), enhanced behavior, plus
a library of original skills the gstack base doesn't ship.

### Whose name is it

Sharing a name is the point of a wrapper, and it needs a rule, because
Claude Code ships built-in commands of its own on a cadence jjstack does not
control. jjstack shadows **gstack** names by design — that is the contract.
It shadows a **Claude Code** built-in only when the built-in stays reachable
under another name, and the skill declares it in frontmatter
(`shadows: - "claude-code:/review -> /code-review"`) so the check can hold
it to that. Otherwise the skill takes a `jj-` prefix. Today: `/review` keeps
its name (Claude's reviewer answers to `/code-review`); jjstack's security
audit is `/jj-security-review` (Claude's `/security-review` has no other
name). `bin/jjstack-verify-skills` fails on an undeclared collision and on a
stale declaration; the built-in list it reads is data in
`references/claude-code-builtins.txt`, regenerated from the installed binary
by `bin/jjstack-builtins-refresh`, and the check warns when your Claude Code
is newer than the list. It runs on every pull request.

### Which tree is live

`~/.claude/skills/jjstack` is what every Claude Code session on this machine
loads. `./setup` points it at a **pinned worktree**, not at your working
checkout, so the branch you have checked out is never what other sessions
execute. The pin lives in `~/.jjstack/skills-pin` and moves only when someone
moves it:

```bash
bin/jjstack-skills-pin --status     # what is live right now
bin/jjstack-skills-pin              # advance it to origin/main
bin/jjstack-skills-pin v0.42.0      # or to a tag, branch or sha
```

`jjstack-upgrade` advances it for you after a pull. Hooks are installed by
copy for the same reason and have been since the permission gate landed; this
is the skills half of that decision.

It is a worktree rather than a copy because the served tree stays a real git
tree: `VERSION`, `git show origin/main:VERSION` and the update check keep
working with no special case, advancing is one `git checkout --detach`, and
going back to any earlier release is the same command with a tag. Your
checkout is never touched by any of it.

What it does **not** buy you is editing a skill and having the change be live.
Testing a change on the live tree means committing it and re-pinning:

```bash
git commit -am "wip"
bin/jjstack-skills-pin HEAD      # serve your branch, deliberately
bin/jjstack-skills-pin           # put the release back
```

That is an install step, just a git-shaped one. It is the price of the
machine not following your working tree by accident.

Without this, a `git checkout` in the maintainer's clone silently changed what
every session on the box executed. It happened: an in-flight pull request
branch was this machine's `/review` for hours, and the reviewer of that very
pull request had to pin a worktree by hand to produce a verdict that could say
which reviewer produced it.

If jjstack was installed from a tarball rather than a clone there is no repo
to hang a worktree off, so `setup` serves the directory directly and says so.

### Who reviews it

Nothing merges on the author's say-so. Rung 4 of the Definition of Done is an
independent review: a Claude Code session that did not write the code, in its
own directory and under its own GitHub identity, runs `/review` on the pull
request and approves it. Every push that answers findings is followed by a
re-request, and the merge waits for an approval newer than the last commit.
A review you run on your own PR still runs, and still helps before you hand
the change over; it just does not satisfy the rung, and `/review` says so.
On InboundSavvy repositories a human (Andre or Santiago) is asked after the AI
round is clean; on disciplin.run and personal repositories one AI review is
enough. `references/independent-review.md` has the table, both sides of the
protocol, and the branch-protection settings that make the rule a floor rather
than prose.

---

## The Three Pillars

jjstack ships three deeply integrated knowledge bases — each with a
**philosophy reference** (the why) and an **adversarial review skill**
(the audit). They cross-reference each other but never duplicate.

| Discipline | Philosophy Reference | Review Skill | What it audits |
|------------|---------------------|--------------|----------------|
| **Product** | `product-management.md` (12 sections) | `/product-manager-review` | OKR alignment, Kano, scope, JTBD, kill list |
| **QA** | `qa-philosophy.md` (11 sections) | `/qa-review` | Test depth, type balance, production verification, mutation score |
| **Code** | `coding-dna.md` + `unit-test-philosophy.md` | `/unit-test-builder` + `/python-coder` | Coding DNA, adversarial testing, mutation testing |

Together they implement the full vision-to-code stack:

```
Vision (century)
  └─ Mission (decade, BHAG)
       └─ SMAC Recipe (years)
            └─ Product-Led OKRs (quarterly: 3 KRs — Quantity / Quality / Efficiency)
                 └─ KPIs (daily measurement, visible to all)
                      └─ Extended Kano Model (10 levels, Steam Train)
                           └─ BDD Gherkin Hierarchy (Capability → Feature → Behavior)
                                └─ API First → CLI → GUI
                                     └─ Primitives Over Frameworks
                                          └─ Test-Driven Development
                                               └─ Coding DNA (security-first, cost-efficient)
```

Load it any time with `/dev-philosophy`. Apply a layer with `/kano-model`,
`/product-manager-review`, `/qa-review`, or `/unit-test-builder`.

---

## Quick Start

```bash
git clone https://github.com/Disciplin-run-org/jjstack.git ~/.claude/skills/jjstack
cd ~/.claude/skills/jjstack && ./setup
```

Setup auto-installs gstack if missing, downloads security review references
(Anthropic, Sentry, OWASP), and links every jjstack skill into
`~/.claude/skills/`. Open Claude Code in any repo and start shipping.

**Prerequisites:** [Claude Code](https://claude.ai/claude-code), `git`,
`jq`, `curl`. No build step. No daemon. No dependencies you don't already
have on a developer machine.

---

## What it changes vs gstack

| Enhancement | gstack | jjstack |
|-------------|--------|---------|
| Review quality target | 8/10 | **10/10** (configurable) — `/cso`, `/qa`, the `plan-*-review` family |
| Quality iterations | 3 max | 3 + fresh-reviewer adversarial passes (same skills; `/review` is budgeted instead) |
| `/review` inputs | The diff | The diff **plus** your repo's real typechecker/linter/test results, the callers outside the diff, and the change's stated intent |
| `/review` noise control | Suppress low-confidence findings | Quoted line + concrete failure scenario + 0–100 confidence, and a budget: 60 min, 4 passes, 10 findings |
| `/review` on re-run | Reports everything again | Verifies only prior P0/P1; returns `STOP` if the finding count did not fall |
| Output location | `~/.gstack/` (invisible) | **`{repo}/jjstack/`** (version-controlled) |
| DNA injection | None | Pluggable voice + coding standards |
| README maintenance | None | Auto-create/update after every skill run |
| Permission friction | Manual approve every time | Deterministic deny floor; long runs never stop to ask |
| MCP resilience | Manual reconnect | Auto-reconnect with retry tracking |
| Auto-updates | gstack-only | jjstack checks on every skill use |
| Prompt-injection guard | None | PreToolUse hook scans markdown writes |
| Failure log | None | PostToolUse hook records non-zero bash exits for promotion |

Wrapper skills keep gstack's command names — `/plan-ceo-review`,
`/plan-eng-review`, `/qa`, `/review`, `/ship`, etc. — and add the
enhancements transparently.

---

## Skills

42 skills across product, QA, code, security, ops, and meta. Highlights:

### Product Management
| Skill | What it does |
|-------|--------------|
| `/product-manager-review` | Adversarial PM audit across 8 dimensions. Outputs kill list. |
| `/kano-model` | Loads Extended Kano Model (Steam Train, 10 levels). |
| `/dev-philosophy` | Loads the full 11-layer Vision-to-Code framework. |
| `/office-hours` | Design doc workflow with quality loop and DNA injection. |

### QA & Testing
| Skill | What it does |
|-------|--------------|
| `/qa-review` | QA health audit across 8 dimensions. Outputs test kill list. |
| `/unit-test-builder` | Generate TDD test suites with adversarial thinking. |
| `/jj-qa` | QA operational rules: cleanup, Docker-first, Kano-driven depth. |
| `/qa` / `/qa-only` | Wrapper skills with jj-qa rules and quality loop. |

### Security & Code Review
| Skill | What it does |
|-------|--------------|
| `/jj-security-review` | 10-phase security audit combining Anthropic + Sentry + OWASP. Carries the `jj-` prefix because Claude Code's own `/security-review` has no other name. |
| `/cso` | Adversarial security audit with quality loop to 10/10. |
| `/review` | Pre-landing review under a budget: deterministic pre-flight (your tooling, blast radius, stated intent), four passes, verified findings, APPROVE/CAUTION/REJECT, and a short verdict posted to the PR with the full report collapsed beneath it. Finishes in under an hour; `--deep` for the exhaustive sweep. Also the name of Claude Code's built-in reviewer; type `/code-review` for that one. |
| `/two-stage-review` | Spec compliance first, then code quality. |
| `/receiving-code-review` | Systematic processing of review feedback (no silent capitulation). |

### Engineering & Ops
| Skill | What it does |
|-------|--------------|
| `/python-coder` | Python coding with embedded test mechanics (Hypothesis, mutmut). |
| `/heal` | Infrastructure heal framework — your senior Ops Manager. |
| `/mcp-server` | Scaffolds FastMCP servers with streamable HTTP. |
| `/github-setup` | Repo init with semver auto-bump GitHub Actions. |
| `/ship` / `/land-and-deploy` | Full ship-and-verify workflow. |
| `/investigate` | Root cause analysis with verified contributing-factors tree. |
| `/canary` | Post-deploy monitoring against production baselines. |

### Meta & Workflow
| Skill | What it does |
|-------|--------------|
| `/save-and-exit` | Keep the session's lessons, then end it. Sweeps memory, settles the Quartermaster ledger, exits cleanly. |
| `/save-and-clear` | Keep the lessons, then start a DIFFERENT task with a clean context. Hands nothing to the next session. |
| `/rollover` | Continue THIS work in a fresh context. The only verb that writes a handover and points a successor at the transcript. |
| `/resume-from-clear` | The entry side of a rollover: read the handover, read the whole previous transcript, verify live state, continue. |
| `/state-doc` | Live `STATE.md` that survives `/clear`, `/compact`, restarts. |
| `/work-order` | Context/Deliverables/Verify/Done template for sub-agent delegation. |
| `/lean` | Cost-lean execution — explicit budgets, no polishing loops. |
| `/worktrees` | Git worktrees for parallel branches and isolated experiments. |
| `/verify-before-done` | Mandatory pre-completion gate that captures real test/lint output. |
| `/writing-skills` | Meta-skill for authoring new jjstack skills. |
| `/jjstack-repair` | Repairs symlinks after gstack updates overwrite them. |

Plus wrapper enhancements for `/plan-ceo-review`, `/plan-eng-review`,
`/plan-design-review`, `/plan-devex-review`, `/design-review`,
`/design-consultation`, `/design-shotgun`, `/design-html`, `/document-release`,
`/retro`, `/autoplan`, `/checkpoint`, `/codex`, `/freeze`, `/guard`, `/learn`,
`/medical-translation-qa`, `/setup-deploy`, `/setup-browser-cookies`,
`/gdocs-writer`, `/devex-review`, and more.

Run any skill in Claude Code. The descriptions trigger automatically on
relevant phrases.

---

## The Reference Library

jjstack ships 22 reference documents — the encoded knowledge each skill
loads. Read them directly or let skills load them for you.

| Reference | What's inside |
|-----------|--------------|
| `dev-philosophy.md` | The 11-layer Vision → Mission → SMAC → OKRs → KPIs → BDD → API-first → Primitives → TDD → DNA stack |
| `coding-dna.md` | 32 Always rules, 23 Never rules, 18 Anti-AI Tells. Calibration anchors with real examples. |
| `kano-model.md` | Extended Kano (Steam Train, 10 levels) for feature prioritization and kill discipline |
| `product-management.md` | 4P:90 framework, OKR Quantity/Quality/Efficiency, JTBD, RICE, scope control toolbox, agentic PM |
| `qa-philosophy.md` | Test type taxonomy, testing trophy, four-bucket failure triage, AI/MCP testing traps, production QA |
| `unit-test-philosophy.md` | Adversarial thinking, boundary analysis, mutation testing, property-based testing |
| `review-preflight.md` | What `/review`'s deterministic pre-flight establishes before any model judges, and which of its statuses are gaps rather than passes |
| `pr-comment-voice.md` | How a review sounds when it is posted to a PR: conclusion first, one line per finding, never a credential |
| `product-identity.md` | The required `## Product Identity` preamble for design docs and CEO reviews |
| `quality-loop.md` | Iteration protocol — fix AI-FIXABLE, escalate NEEDS-HUMAN, exit at score or convergence |
| `root-cause-analysis.md` | Verified contributing-factors tree (replaces 5 Whys with evidence-gated nodes) |
| `spec-cleanup-playbook.md` | Five smell tests for capability-level spec cleanup before the QA loop |
| `hard-gate-convention.md` | The HARD-GATE pattern for skills that must block until verified |
| `definition-of-done.md` | The canonical 11-rung "done-done" Definition of Done + reporting rule |
| `independent-review.md` | Rung 4: who reviews a PR before merge (the AI reviewer session, then a human on InboundSavvy repos), why the author never reviews their own, the reviewer identity, and the branch-protection settings |
| `memory-promotion.md` | When recurring patterns should be promoted to memory or skills |
| `output-capture.md` | Protocol for copying gstack outputs into `{repo}/jjstack/` |
| `memory-sweep.md` | The shared base all three session-boundary skills run — what to keep before the context goes |
| `qm-ledger-settle.md` | How `/save-and-clear` and `/save-and-exit` close out their Quartermaster items instead of stranding them |
| `specimen-recovery.md` | A guard must exhibit text it matches: derive the specimen from the artifact, never author it from the pattern |
| `rollover-handover.md` | The contract between `/rollover` and `/resume-from-clear`: what the handover carries and which carrier delivers it |
| `capture-classifier.md` | The headless prompt that extracts durable lessons from a transcript as JSON |
| `owasp-security/` | Language-specific security quirks — the layer below `/jj-security-review` |

These references are the durable layer. Skills come and go; the philosophy
stays.

---

## Hooks

jjstack ships seven optional hooks that ride along with every Claude Code
session.

**`permission-floor.py`** — The permission gate: a `PreToolUse` hook on
`Bash` that refuses eleven shapes and lets everything else run without
asking anyone. It calls nothing and needs no API key.

Ten rules are the floor — commands whose reach is unbounded (`rm -rf ~`,
`chmod -R 777 /`), whose content nobody has read (`curl … | sh`), that send
a local file or a known secret path to the network, that write to a block
device, that power the machine down, or that force-push the trunk. The
eleventh is `SHAPE`: one command per Bash call. A chained call is refused
with instructions to split it, which is both a readability rule and what
makes the other ten exact — `S=/tmp/x; rm -rf $S` begins with an
assignment, so no prefix rule the permission system has ever sees the `rm`.
Heredoc bodies and quoted strings are excluded from that scan, so writing a
commit message or a fixture file stays one call.

Refusals are `deny`, not `ask`: Claude is told the rule and the fix and
reroutes inside the same turn, so an unattended run never stops for a
person. `test/settings-lint.sh` checks the installed policy and
`bin/jjstack-permission-audit --since 24h` reports how often anyone was
actually interrupted.

**`auto-approve-safe.sh`** — A `PermissionRequest` hook that decides
nothing. It writes the audit line the permission audit reads, and hands the
request to the tubemail forwarder so an orchestrator can answer the few
residual prompts remotely with `tm_respond_permission`. It has no `allow`
branch, deliberately: a hook that can approve is a hook that can be a
bypass.

**`shared-memory.sh`** — A UserPromptSubmit hook that recalls relevant memory
into every prompt (see [Memory](#memory)): deterministic always-rules,
branch decisions, this project's own notes, pan-project preferences, and
cross-project lessons — surfaced semantically, wrapped in a do-not-interpret
envelope, with a cross-project/PHI firewall.

**`capture-on-end.sh`** — A SessionEnd hook that auto-captures durable lessons
from the finished session (see [Memory](#memory)). It enqueues and detaches
in milliseconds so it never blocks exit; a background worker extracts lessons
and writes them PHI-gated and deduplicated. Disable with `JJSTACK_NO_CAPTURE=1`.
Deduplication runs in two layers: an exact `pattern_key` match, then a semantic
near-duplicate lookup against gbrain. The semantic layer merges the new lesson
into the page it matched only at or above the merge threshold `0.85`; anything
scoring below that becomes a new memory instead. `JJSTACK_CAPTURE_NO_GBRAIN=1`
pins the semantic layer off, for offline use or a repeatable answer; exact-key
dedup still runs. That lookup runs under a deadline, default 8 seconds, changed
with `JJSTACK_CAPTURE_GBRAIN_TIMEOUT=<seconds>`. Every capture reports which
state the layer reached — `ran-clean`, `ran-timeout`, `ran-error:<rc>`, or
`not-run:<reason>` — because a killed query returns empty, which otherwise reads
exactly like "no duplicate found". Only `ran-clean` means an answer was used.

**`injection-guard.sh`** — A PreToolUse hook on `Write`/`Edit` that scans
markdown headed for disk and blocks high-confidence prompt-injection
patterns before they land in a file that a future model read might execute.
Categories blocked include override-instruction phrases, fake system-tag
framing, Unicode tag steganography (U+E0000 range), role-reprogramming
language, and imperative tool-invocation framing. High-precision by design;
non-markdown writes are skipped entirely.

**`error-detector.sh`** — A PostToolUse hook on `Bash` that records every
non-zero exit to `~/.jjstack/command-failures.jsonl`. Patterns recurring
3+ times become candidates for promotion to memory or a skill. Query with:

```bash
jq -r '.command' ~/.jjstack/command-failures.jsonl | sort | uniq -c | sort -rn | head
```

**`mcp-reconnect.sh`** — A PostToolUseFailure hook that reconnects MCP
servers automatically on disconnection. Up to 3 retries before escalating.

---

## Memory

jjstack gives Claude Code a cross-session memory that recalls the right
lessons at the right time, captures new ones automatically, and consolidates
duplicates on demand. It layers on gstack's stores and a local vector index
(gbrain) rather than inventing new storage.

**Recall** (the `shared-memory.sh` hook) surfaces, on every prompt: standing
always-rules, branch decisions, this project's own memory notes (semantic),
pan-project preferences ("how you like things done regardless of repo"), and
lessons from your other projects. Everything is keyed on a project's canonical
git-remote identity, and another project's private notes are never surfaced —
a built-in cross-project/PHI firewall.

**Capture** (the `capture-on-end.sh` hook) turns a finished session into
durable lessons with no manual step: a background pass extracts what's worth
keeping and writes it deduplicated, with the PHI gate applied first so
sensitive projects stay local-only.

**Consolidate** (`/groom`, including its `cross` mode) removes sprawl:
near-duplicate memories are clustered and merged with your review, and a
lesson you've told several projects can be promoted to the pan-project store.
A promoted memory is marked so it is never silently re-created.

**PHI safety.** Sensitive projects opt out (a `.no-gbrain` marker or a
git-remote policy of `deny`/`read-only`); their memories stay in local native
files only and never reach the shared index. This is enforced in one shared
library that every memory tool uses.

Regression coverage lives in `test/smoke.sh`. It is hermetic: every assertion
runs against a throwaway home directory, a throwaway PATH with no ambient
gbrain, and throwaway fixture projects, so it never reads or writes your real
memory store, learnings or gbrain index, and gives the same verdict on any
machine. The suite lints itself for that property, and it tests its own
assertion harness first — a broken `check()` turns real assertions into silent
passes.

---

## Statusline + Recap

jjstack ships a Claude Code statusline that packs model, project, branch,
context %, usage %, auto-mode, and contextual hints into one band — plus
an inline recap of the last completed task above the prompt.

<p align="center">
  <img src="docs/images/jjstack-statusline.png" alt="jjstack statusline showing model Opus 4.7 with xhigh effort, project jjstack, branch main with dirty/untracked counts, context 43%, usage 0%, auto mode on, and a recap of the previous completed task with commit hash" width="100%">
</p>

What you see above:

- **Statusline (lower band)** — model + reasoning effort, project, git
  branch with dirty/untracked counts, context usage %, API usage %,
  auto-mode indicator with keyboard cycle hint, save-tokens hint when
  context fills up.
- **Recap (upper band)** — one-line summary of the last completed task
  with the commit hash. Auto-recap is on by default; disable via
  `/config`.
- **Worker label** (top right, `jjstack-tm` here) — tubemail-channel
  name when running as a worker session.

Configure defaults at install time or by editing `~/.jjstack/config`.

---

## Configuration

Global defaults in `jjstack.config.yaml`:

```yaml
review:
  min_score: 10           # quality target (gstack default: 8)
  max_iterations: 3       # additional passes after gstack's loop

output:
  location: repo          # "repo" or "home"
  repo_subdir: jjstack    # subdirectory name in repo

dna:
  voice: null             # path to voice DNA file (optional)
  coding: ~/.claude/skills/jjstack/references/coding-dna.md
```

Per-project override in `.jjstack.config.yaml` at your repo root. Keys
merge on top of global defaults — set `min_score: 8` in a prototype to
ease the gate, leave it at 10 in production code.

---

## How it works

Two architectural patterns:

**Wrapper skills** (most of the catalog) — read jjstack config, optionally
load DNA files, then delegate to the corresponding gstack skill via
`cat`. After gstack completes, jjstack runs post-enhancement: quality loop
to 10/10, output capture into `{repo}/jjstack/`, README maintenance.

**Layered skills** (`/jj-security-review`, `/product-manager-review`,
`/qa-review`, `/unit-test-builder`) — pure jjstack skills that load
multiple reference documents and run their own multi-phase pipelines with
sub-agent verification.

Install replaces gstack's symlinks in `~/.claude/skills/` with jjstack
symlinks. Same command names. Enhanced behavior. Uninstall restores the
originals.

---

## Auto-updates

jjstack checks for updates on first skill use (cached 60 minutes). When a
new version is available, you're asked to upgrade. Updates are a
`git pull` — symlinks resolve to new content immediately. Security review
references (Anthropic, Sentry) auto-update on each `./setup` run via
`git pull --ff-only`.

---

## Battle-tested

jjstack powers an active multi-product ecosystem:

- **LeanSpecs** — hierarchical product spec framework with BDD generation
- **Iris-QA** — hybrid QA framework (pytest-bdd + AI augmentation)
- **Quartermaster** — engineering-manager orchestrator routing work between
  Claude Code workers
- **TubeMail** — transport layer for inter-session work routing
- **Actuatrix** — independent KPI engine

Every spec, every test, every commit in those repos passes through jjstack
skills. The friction it removes is real. The discipline it enforces is real.

---

## Related tools

jjstack intentionally does not ship the full
[`obra/superpowers`](https://github.com/obra/superpowers) methodology —
several superpowers skills overlap with jjstack's own variants
(`/office-hours`, `/plan-*-review`, `/ship`, `/review`, `/land-and-deploy`)
and carry more differentiated jjstack conventions. jjstack has borrowed
the patterns it found most valuable (`/two-stage-review`, `/worktrees`,
`/verify-before-done`, `/writing-skills`, `/receiving-code-review`, the
HARD-GATE convention) with attribution.

If you want the full superpowers methodology in parallel:

```bash
/plugin install superpowers@claude-plugins-official
```

Both distributions coexist. Pick either per task; use both when the
workflows compose.

---

## Acknowledgments

- [gstack](https://github.com/garrytan/gstack) by Garry Tan — the foundation jjstack stands on
- [obra/superpowers](https://github.com/obra/superpowers) — patterns borrowed and attributed
- [Anthropic](https://github.com/anthropics) — official security-review methodology
- [Sentry](https://github.com/getsentry) — investigation-first security methodology
- [agamm/owasp-security](https://github.com/agamm/skill-owasp-security) — OWASP Top 10:2025 + Agentic AI ASI
- Andrej Karpathy — for the prompt that started this: "I don't think I've typed like a line of code probably since December"

---

## Uninstall

```bash
cd ~/.claude/skills/jjstack && ./uninstall
```

Restores original gstack symlinks. Removes only jjstack-specific hook
entries (preserves your other hooks). Your project output
(`{repo}/jjstack/`) and config files are left intact.

---

## License

MIT — see [LICENSE](LICENSE).

Use it. Fork it. Make it your own. If you ship something cool with it,
let me know.
