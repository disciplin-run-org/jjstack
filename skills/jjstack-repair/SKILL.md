---
name: jjstack-repair
description: >
  Repair jjstack after gstack overwrites skill symlinks. Run this when
  /review, /qa, /plan-ceo-review etc. show gstack descriptions instead
  of jjstack's. Also checks for updates and shows jjstack status.
  Trigger on: "fix jjstack", "repair jjstack", "jjstack status",
  "jjstack broken", "skills pointing to gstack".
allowed-tools:
  - Bash
  - Read
---

# jjstack repair

Fix jjstack skill symlinks and show status.

## Step 1: Fix symlinks

```bash
~/.claude/skills/jjstack/bin/jjstack-fix-symlinks
```

If output contains `SYMLINKS_FIXED`, report how many were repaired.
If no output, all symlinks are correct.

## Step 2: Check for updates

```bash
~/.claude/skills/jjstack/bin/jjstack-update-check --force
```

Report the result.

## Step 3: Show status

```bash
cat ~/.claude/skills/jjstack/VERSION
```

Report the jjstack version and confirm all skills are operational.
