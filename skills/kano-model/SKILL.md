---
name: kano-model
description: >
  Load the 10-level Extended Kano Model (Steam Train). Injects the full
  prioritization framework so every feature justifies its existence, QA depth,
  and quality tolerance. Use when prioritizing features, setting QA depth,
  reviewing specs, or deciding what to build/kill. Trigger on: "kano model",
  "kano level", "feature priority", "what kano", "steam train", "QA depth",
  "quality tolerance", "should we build this".
allowed-tools:
  - Read
  - Bash
---

# Extended Kano Model — Steam Train

Load and apply the 10-level functionality prioritization framework.

```bash
cat ~/.claude/skills/jjstack/references/kano-model.md
```

After loading, identify which Kano level applies to the current feature and
use it to determine minimum QA depth, quality tolerance, and whether the
feature should exist. QA depths are MINIMUMS — always strive higher.
