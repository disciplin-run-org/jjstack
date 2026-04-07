---
name: dev-philosophy
description: >
  Load the 11-layer development philosophy. Injects the full framework from
  Vision to Code so every decision is grounded in context. Use at the start
  of a new project, when explaining the approach to a colleague or AI, or
  when a conversation drifts from principles. Trigger on: "dev philosophy",
  "explain our approach", "how do we develop", "what's our process",
  "start new project", "what layer are we at".
allowed-tools:
  - Read
  - Bash
---

# Development Philosophy

Load and apply the 11-layer development philosophy.

```bash
cat ~/.claude/skills/jjstack/references/dev-philosophy.md
```

After loading, identify which layer is relevant to the current task and work
within that layer's constraints. If a higher layer is undefined (e.g., no OKRs
exist for this project), flag it — don't skip it silently.
