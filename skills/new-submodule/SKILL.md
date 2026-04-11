---
name: new-submodule
description: >
  Create a new git submodule in the ai-agents ecosystem. Handles GitHub repo creation,
  submodule wiring, README with role definition, Claude memory setup, port allocation,
  and monorepo memory updates. Trigger on: "new submodule", "new module", "create a
  new service", "add a new tool to the ecosystem", or when naming a new dev ecosystem
  member (architect, KPI engine, coder, etc.).
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - mcp__plugin_github_github__create_repository
---

# New Submodule — ai-agents Ecosystem

Creates a new git submodule service in the ai-agents monorepo. Every ecosystem module
follows the uniform module contract: git submodule, shared library, MCP server, web UI.

## Prerequisites

Confirm you are in the ai-agents monorepo root:
```bash
git -C /home/jesper/PycharmProjects/ai-agents remote -v
```

## Step 1: Gather Information

Use AskUserQuestion if any of these are missing from the user's request:

1. **Name** — the module name (e.g., architrix, actuatrix, iris-qa)
2. **Role** — one-line role description (e.g., "KPI calculation, OKR progress, forecasts")
3. **Ecosystem position** — where it fits in the hierarchy:
   ```
   Quartermaster (orchestrator)
   ├── Product Manager (LeanSpecs) — WHAT to build, WHY
   ├── Architect (Architrix) — HOW to build, data contracts, task breakdown
   ├── KPI Engine (Actuatrix) — MEASURES progress, forecasts, reports
   ├── Coders (Claude Code sessions) — build the tasks
   └── QA (Iris-QA) — verify it works
   ```

## Step 2: Allocate Port

Read the current port allocation and assign the next available:

```bash
grep -E "MCP_PORT|port:" /home/jesper/PycharmProjects/ai-agents/docker-compose.yml | head -20
```

Current allocation:
| Service | Port |
|---------|------|
| LeanSpecs | 8001 |
| Google Workspace MCP | 8002 |
| Iris-QA | 8003 |
| Architrix | 8004 |
| Actuatrix | 8005 |

Assign the next unused port.

## Step 3: Create GitHub Repository

```
mcp__plugin_github_github__create_repository
  name: <module-name>
  description: <role description>
  private: true
  autoInit: true
```

## Step 4: Add as Git Submodule

```bash
git -C /home/jesper/PycharmProjects/ai-agents submodule add https://github.com/JesperJurcenoks/<module-name>.git <module-name>
```

## Step 5: Write README

Write `<module-name>/README.md` with this structure:

```markdown
# <Module Name>

<One-line description of what it does.>

## Role in the Dev Ecosystem

<ASCII hierarchy diagram showing where this module fits>

## What <Module Name> Owns

<Numbered sections describing each responsibility>

## Tech Stack

- MCP server (Python, FastMCP) — same pattern as all ecosystem services
- Uses `shared/` library (BaseConfig, app_factory, health, etc.)
- Docker container in the ai-agents docker-compose

## Ports

<Table of all service ports including this new one>

## Origin

<Brief explanation of the name>
```

Key content to include:
- The boundary between this module and its neighbors (who does WHAT vs HOW)
- What data it consumes and produces
- First tasks or features it will implement

## Step 6: Commit and Push Submodule

```bash
git -C /home/jesper/PycharmProjects/ai-agents/<module-name> add README.md
```

```bash
git -C /home/jesper/PycharmProjects/ai-agents/<module-name> commit -m "$(cat <<'EOF'
docs: initial README with <module role> scope

<2-3 line description of what was defined.>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

```bash
git -C /home/jesper/PycharmProjects/ai-agents/<module-name> push
```

## Step 7: Create Claude Memory Directory

```bash
mkdir -p ~/.claude/projects/-home-jesper-PycharmProjects-ai-agents-<module-name>/memory
```

Write three memory files:

### MEMORY.md (index)
```markdown
# <Module Name> Memory

## Project Overview
- [Project Role](project_role.md) — <Module>'s role in the dev ecosystem
- [<Domain-specific memory>](<filename>.md) — <description>
```

### project_role.md
```markdown
---
name: <Module> role in dev ecosystem
description: <one-line description>
type: project
---

<Module> is the <role> in the ai-agents dev ecosystem.

**Why:** <Why this module exists as a separate concern>

**How to apply:** <Boundary rules — what belongs here vs neighboring modules>

The full hierarchy:
<ASCII diagram>
```

### Domain-specific memories
Create 1-2 additional memory files capturing:
- Key design decisions from the conversation that created this module
- First tasks or features to implement
- Any user preferences or constraints discussed

## Step 8: Update Monorepo Memory

Edit the dev orchestrator design memory to include the new module in the roster:

```
/home/jesper/.claude/projects/-home-jesper-PycharmProjects-ai-agents/memory/project_dev_orchestrator_design.md
```

Add the new module to the "Full Module Roster" table.

## Step 9: Verify

```bash
git -C /home/jesper/PycharmProjects/ai-agents submodule status
```

Confirm the new submodule appears in the list.

```bash
ls ~/.claude/projects/-home-jesper-PycharmProjects-ai-agents-<module-name>/memory/
```

Confirm memory files exist.

## Handoff

Tell the user:
> **<Module Name>** is set up:
> - GitHub repo: `JesperJurcenoks/<module-name>` (private)
> - Submodule: `ai-agents/<module-name>/`
> - Port: <port>
> - Claude memory: ready with <N> files
>
> Start Claude Code from `ai-agents/<module-name>/` and run `/office-hours` there.

## Notes

- Do NOT create docker-compose entries, Dockerfiles, or code yet — that happens
  during `/office-hours` and implementation
- Do NOT create a LeanSpecs product.json — the module's own `/office-hours` session
  will define its spec
- The README captures the role and scope. Implementation details come later.
- Each Bash call must be a single command (no && chaining per CLAUDE.md rules)
