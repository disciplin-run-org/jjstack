---
name: jjstack-repair
description: >
  Repair jjstack after gstack overwrites skill symlinks. Run this when
  /review, /qa, /plan-ceo-review etc. show gstack descriptions instead
  of jjstack's. Also refreshes the statusline to jjstack's current
  version, checks for updates, and shows jjstack status.
  Trigger on: "fix jjstack", "repair jjstack", "jjstack status",
  "jjstack broken", "skills pointing to gstack", "statusline broken",
  "refresh jjstack statusline".
allowed-tools:
  - Bash
  - Read
---

# jjstack repair

Fix jjstack skill symlinks, refresh the statusline, and show status.

## Step 1: Fix symlinks

```bash
~/.claude/skills/jjstack/bin/jjstack-fix-symlinks
```

If output contains `SYMLINKS_FIXED`, report how many were repaired.
If no output, all symlinks are correct.

## Step 2: Refresh the statusline

```bash
~/.claude/skills/jjstack/bin/jjstack-statusline-install
```

Report what happened:
- `installed` — no statusline was set; jjstack's is now active
- `already installed` — jjstack's statusline is current; nothing to do
- `refreshed (path changed)` — jjstack's statusline path changed (you
  probably relocated the jjstack clone); the settings were updated
- `skipped (kept existing)` — a non-jjstack statusline was detected.
  Show the existing command to the user and offer to force-overwrite
  via `~/.claude/skills/jjstack/bin/jjstack-statusline-install --force`
  if they want jjstack's instead. Do NOT force-overwrite without
  their explicit confirmation.

## Step 3: Check for updates

```bash
~/.claude/skills/jjstack/bin/jjstack-update-check --force
```

Report the result.

## Step 4: Show status

```bash
cat ~/.claude/skills/jjstack/VERSION
```

Report the jjstack version and confirm all skills are operational.
