# jjstack

A derived distribution of [gstack](https://github.com/garrytan/gstack) that enhances Claude Code workflows with higher quality thresholds, repo-local output, and new skills.

jjstack wraps gstack skills with the same command names — no new commands to learn. Type `/plan-ceo-review` and get jjstack's enhanced version transparently.

## What it changes

| Enhancement | gstack default | jjstack |
|-------------|---------------|---------|
| Review quality target | 8/10 | 10/10 (configurable) |
| Quality iterations | 3 max | 3 additional passes with fresh reviewer |
| Output location | `~/.gstack/projects/` (local, invisible) | `{repo}/jjstack/` (version-controlled) |
| DNA injection | None | Pluggable voice + coding standards |
| README maintenance | None | Auto-create/update after every skill run |
| Permission friction | Manual approve | Smart auto-approve hook (Haiku risk classification) |
| MCP resilience | Manual reconnect | Auto-reconnect hook with retry tracking |
| Auto-updates | gstack-only | jjstack checks for updates on first use |

## Prerequisites

- [gstack](https://github.com/garrytan/gstack) >= 0.11.0 (installed automatically if missing)
- [Claude Code](https://claude.ai/claude-code) with skills support
- `jq` and `curl` (for the auto-approve hook)
- Git repo (for repo-local output; falls back to `~/.gstack/projects/` outside repos)

## Install

```bash
git clone https://github.com/JesperJurcenoks/jjstack.git ~/.claude/skills/jjstack
cd ~/.claude/skills/jjstack && ./setup
```

You can also clone to a different location (e.g., `~/Projects/jjstack`) — setup
will create a symlink from `~/.claude/skills/jjstack` to wherever you cloned it.

Setup installs gstack automatically if not present, downloads security review
dependencies (Anthropic, Sentry, OWASP), and creates symlinks in `~/.claude/skills/`
so jjstack skills are available in every Claude Code session.

## Uninstall

```bash
cd ~/.claude/skills/jjstack && ./uninstall
```

Restores original gstack symlinks and removes only jjstack-specific hook entries (preserves other hooks). Your project output (`{repo}/jjstack/`) and config files are left intact.

## Available skills

### Wrapper skills (override gstack)

| Skill | What it adds |
|-------|-------------|
| `/plan-ceo-review` | Quality loop to 10/10, repo-local output, DNA injection |
| `/plan-eng-review` | Same enhancements for engineering review |
| `/plan-design-review` | Same enhancements for design plan review |
| `/office-hours` | Output redirect to repo, quality loop, DNA injection |
| `/review` | Deeper adversarial passes (configurable, default 2) |
| `/design-review` | Responsive design rules, Google Fonts-only |
| `/design-consultation` | Design system saved to repo, DNA injection |
| `/qa` | QA reports to repo, jj-qa rules, quality loop |
| `/qa-only` | QA report-only with jj-qa rules |
| `/cso` | Security audit to repo, quality loop, DNA injection |
| `/ship` | Ship workflow with jjstack conventions |
| `/investigate` | Root cause analysis to repo, DNA injection |
| `/retro` | Retrospective to repo, DNA injection |
| `/document-release` | Post-ship docs to repo, DNA injection |
| `/autoplan` | Auto-review pipeline to repo, quality loop |

### New skills (jjstack originals)

| Skill | What it does |
|-------|-------------|
| `/security-review` | Comprehensive security review combining Anthropic, Sentry, and OWASP methodologies with MCP-specific CWE assessment, secret detection, supply chain analysis, and STRIDE threat mapping |
| `/heal` | Modular debug/heal framework generator for containerized projects |
| `/mcp-server` | MCP server scaffolding with FastMCP and streamable HTTP |
| `/github-setup` | GitHub repo initialization with semver auto-bump Actions |
| `/python-coder` | Python coding with project conventions |
| `/jj-qa` | QA philosophy and operational rules for testing |
| `/jj-code` | Implementation skill for filling the plan-to-QA gap |
| `/smart-context7` | Intelligent Context7 invocation (avoids wasted API calls) |
| `/smart-review` | Auto-invokes code review plugin before PR creation |
| `/smart-simplify` | Auto-invokes code simplifier after significant changes |
| `/work-order` | Structured Context/Deliverables/Verify/Done template for delegating tasks to sub-agents, workers, PRs, or plan items |
| `/state-doc` | Maintains a repo-root `STATE.md` — live "where we are right now" doc that survives `/clear`, `/compact`, and restarts |
| `/lean` | Cost-lean execution mode: explicit tool-call budget, one-shot writes, no polishing, no iteration loops. For QA loops, ralph-loop, and agent pipelines where every call compounds |
| `/two-stage-review` | Review in two passes: spec compliance first (did you build what was asked?), then code quality (is it good code?). Adapted from obra/superpowers |
| `/worktrees` | Git worktree workflow for parallel branches — isolated trees for subagents, experiments, and concurrent workstreams. Adapted from obra/superpowers |
| `/verify-before-done` | Mandatory pre-completion verification gate — captures test/type/lint/health output in the session before any "done" claim. Adapted from obra/superpowers |
| `/writing-skills` | Meta-skill for authoring new jjstack skills: file layout, frontmatter schema, trigger language, HARD-GATE usage, install-manifest integration, attribution conventions. Adapted from obra/superpowers |
| `/receiving-code-review` | Companion to /review — systematic processing of review feedback (triage by severity, agree/disagree with explicit reasoning, close the loop). Prevents silent capitulation and silent stonewalling. Adapted from obra/superpowers |

### /security-review

The flagship security skill, built from analyzing 24 community security skills and cherry-picking the best from each:

**Sources (loaded at runtime):**
- **Anthropic** official security-review (by-reference, auto-updated) — confidence scoring, 17 exclusion rules, 12 precedent rules, sub-task false-positive verification
- **Sentry** security-review (by-reference, auto-updated) — investigation-first methodology, 17 vulnerability reference files, 5 language guides, 5 infrastructure guides
- **OWASP** Top 10:2025 + ASVS 5.0 + Agentic AI ASI01-10 (by-copy from agamm) — 20 language-specific security quirks

**Modes:** `full` (default), `diff`, `diff:BRANCH`, `focus:auth`, `focus:secrets`, `focus:mcp`, `focus:supply-chain`

**Assessment coverage (10 check categories):**
1. MCP-specific CWE assessment (information disclosure, agentic AI risks)
2. Secret detection (14+ format-specific regex patterns: AWS, GitHub, Stripe, Twilio, SendGrid, Slack, PEM keys, database connection strings)
3. Git history secret scanning (searches ALL commits, not just deleted files)
4. CWE checks (injection, path traversal, SSRF, deserialization, sensitive logging)
5. Insecure defaults detection (fail-open patterns, fallback secrets, debug modes)
6. Entry point analysis (HTTP, MCP, WebSocket, CLI, queues, webhooks)
7. Supply chain risk (single maintainer, unmaintained, suspicious lifecycle scripts)
8. Cryptographic algorithm review (correct vs incorrect algorithm selection table)
9. Security headers check (6 headers for web apps)
10. Claude config self-audit (settings.json, CLAUDE.md, .mcp.json, hooks)

**Output:** STRIDE threat summary, confidence-scored findings (>= 0.8 only), auto-fix for Critical/High.

## Hooks

### Auto-approve hook (`auto-approve-safe.sh`)

Smart permission gate using Claude Haiku for risk classification:
- Read-only tools (Read, Glob, Grep, etc.) are always approved
- Bash commands are sent to Haiku for LOW/MEDIUM/HIGH risk rating
- LOW commands are auto-approved; MEDIUM/HIGH defer to the user
- Fail-closed fallback when API is unavailable: only safe read-only commands are auto-approved; commands with shell metacharacters (`;`, `&&`, `|`, backticks) are always deferred
- Auto-fixes API key file permissions to 600

### Prompt-injection guard (`injection-guard.sh`)

PreToolUse hook on `Write`/`Edit` that scans content headed for `.md` / `.markdown` files and blocks high-confidence prompt-injection patterns before they land on disk:

- "ignore previous/prior/above instructions" family
- "disregard previous/prior/above" family
- Fake system-reminder tags
- Fake `system:` / `<system>` / `<|system|>` line-start framing
- Unicode tag characters (U+E0000–U+E007F) used for steganographic injection
- Role-reprogramming phrases ("you are now a different assistant")
- Imperative tool-invocation instructions ("you must execute the following command")

High-precision / medium-recall by design: false positives annoy humans but are rephraseable; false negatives let injections land where later model reads will execute them. Non-markdown files are skipped entirely. The block surfaces a reason string that explains which pattern matched and how to rephrase.

### MCP auto-reconnect hook (`mcp-reconnect.sh`)

Automatically reconnects MCP servers on disconnection:
- Detects disconnection patterns in MCP tool failures
- Retries up to 3 times before escalating to the user
- Tracks retry count per server in `~/.jjstack/` (user-specific, not `/tmp/`)

## Configuration

### Global defaults

`jjstack.config.yaml` in the jjstack repo root:

```yaml
review:
  min_score: 10           # quality target (gstack default: 8)
  max_iterations: 3       # additional passes after gstack's own loop
  adversarial_passes: 2   # review depth (gstack default: 1)

output:
  location: repo          # "repo" or "home"
  repo_subdir: jjstack    # subdirectory name in repo

dna:
  voice: null             # path to voice DNA file
  coding: ~/.claude/skills/jjstack/references/coding-dna.md
```

### Per-project override

Create `.jjstack.config.yaml` in your project root. Keys merge on top of global defaults.

```yaml
# Example: lower the quality bar for a prototype
review:
  min_score: 8
```

## Auto-updates

jjstack checks for updates on first skill use (cached for 60 minutes). When a new version is available, you'll be asked to upgrade. Updates are a `git pull` — symlinks resolve to new content immediately.

Security review dependencies (Anthropic, Sentry) are also auto-updated on each `./setup` run via `git pull --ff-only`.

## How it works

jjstack uses a **wrapper pattern**: each skill reads its own config, optionally loads DNA files, then delegates to the corresponding gstack skill by reading its SKILL.md. After gstack completes, jjstack runs post-enhancement steps (quality loop, output verification, README maintenance).

The `/security-review` skill uses a **layered pattern** instead: it loads three reference methodologies (Anthropic, Sentry, OWASP) at runtime, then runs its own 10-phase assessment pipeline with sub-agent verification.

The install script replaces gstack's symlinks in `~/.claude/skills/` with jjstack symlinks. Same command names, enhanced behavior. Uninstall restores the originals.

## Related tools

jjstack intentionally does not ship the full `obra/superpowers`
methodology — several superpowers skills (`brainstorming`,
`writing-plans`, `executing-plans`, `requesting-code-review`,
`finishing-a-development-branch`) overlap with jjstack's own variants
(`/office-hours`, `/plan-*-review`, `/ship`, `/review`, `/land-and-deploy`)
and carry more differentiated jjstack conventions. jjstack has borrowed
the patterns it finds most valuable (`/two-stage-review`, `/worktrees`,
`/verify-before-done`, `/writing-skills`, `/receiving-code-review`, the
HARD-GATE convention) with attribution.

If you want the full superpowers methodology in parallel with jjstack,
install it from Anthropic's official marketplace:

```bash
/plugin install superpowers@claude-plugins-official
```

Both distributions coexist — superpowers' skills live under its plugin
namespace and jjstack's skills live under jjstack's. Pick either one
per task; use both when the workflows compose.

## License

MIT
