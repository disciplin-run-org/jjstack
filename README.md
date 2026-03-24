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
| Auto-updates | gstack-only | jjstack checks for updates on first use |

## Prerequisites

- [gstack](https://github.com/garrytan/gstack) >= 0.11.0 (installed and working)
- [Claude Code](https://claude.ai/claude-code) with skills support
- `jq` and `curl` (for the auto-approve hook)
- Git repo (for repo-local output; falls back to `~/.gstack/projects/` outside repos)

## Install

```bash
git clone https://github.com/JesperJurcenoks/jjstack.git ~/.claude/skills/jjstack
cd ~/.claude/skills/jjstack && ./setup
```

This installs gstack automatically if not present, then creates symlinks in `~/.claude/skills/` so jjstack skills are available in every Claude Code session, regardless of which project you're working in.

## Uninstall

```bash
cd ~/.claude/skills/jjstack && ./uninstall
```

Restores original gstack symlinks. Your project output (`{repo}/jjstack/`) and config files are left intact.

## Available skills

### Wrapper skills (override gstack)

| Skill | Status | What it adds |
|-------|--------|-------------|
| `/plan-ceo-review` | Ready | Quality loop to 10/10, repo-local output, DNA injection |
| `/plan-eng-review` | Planned | Same enhancements for engineering review |
| `/office-hours` | Planned | Output redirect to repo |
| `/review` | Planned | Deeper adversarial passes |
| `/ship` | Planned | jjstack conventions |

### New skills

| Skill | Status | What it does |
|-------|--------|-------------|
| `/heal` | Ready | Modular debug/heal framework generator for containerized projects |
| `/jj-code` | Planned | Implementation skill — fills the plan→QA gap |

## Configuration

### Global defaults

`jjstack.config.yaml` in the jjstack repo root. Accessible via the symlink at `~/.claude/skills/jjstack/jjstack.config.yaml`.

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
  coding: null            # path to coding DNA file
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

## How it works

jjstack uses a **wrapper pattern**: each skill reads its own config, optionally loads DNA files, then delegates to the corresponding gstack skill by reading its SKILL.md. After gstack completes, jjstack runs post-enhancement steps (quality loop, output verification, README maintenance).

The install script replaces gstack's symlinks in `~/.claude/skills/` with jjstack symlinks. Same command names, enhanced behavior. Uninstall restores the originals.

## Contributing

1. Fork and clone
2. Add a new skill in `skills/{name}/SKILL.md` or enhance an existing wrapper
3. Run `bash install.sh` to test locally
4. Submit a PR

See `docs/jesper-main-design-20260322-234024.md` for the full architecture.

## License

MIT
