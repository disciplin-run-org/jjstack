# Hermes Skin / Color Debugging Reference

## Symptom
Dark-grey or invisible text in the Hermes status bar — parts of the CLI UI are unreadable.
Reported on black/dark terminal backgrounds with the default gold skin.

## Root Cause
The builtin `default` skin defines `status_bar_bg: #1a1a2e` (dark navy) but omits all
`status_bar_text`, `status_bar_dim`, `status_bar_strong`, `status_bar_good`, `status_bar_warn`,
`status_bar_bad`, `status_bar_critical`. The text color falls back to the terminal's default
foreground, which on a black terminal is dark grey — invisible against dark navy.

## Diagnostic Path

1. Check current skin config:
   ```bash
   hermes config show
   # Look for display.skin and display.skin_overrides
   ```

2. Inspect the skin engine source to see what keys the builtin skin defines:
   ```
   /data/hermes/hermes-agent/hermes_cli/skin_engine.py
   ```
   Search for `_BUILTIN_SKINS["default"]` — check which `status_bar_*` keys are present.

3. Compare against `slate` which has a complete status bar color set as a working reference.

## Fix Applied (Jesper's machine, July 2026)

Kept the default skin but patched in the missing status bar text colors:

```bash
hermes config set display.skin default
hermes config set display.skin_overrides.colors.status_bar_text "#C0C0C0"
hermes config set display.skin_overrides.colors.status_bar_strong "#FFD700"
hermes config set display.skin_overrides.colors.status_bar_dim "#8B8682"
hermes config set display.skin_overrides.colors.status_bar_good "#4caf50"
hermes config set display.skin_overrides.colors.status_bar_warn "#ffa726"
hermes config set display.skin_overrides.colors.status_bar_bad "#ef5350"
hermes config set display.skin_overrides.colors.status_bar_critical "#FF5252"
```

Takes effect on next `hermes` session start.

## Alternative: Switch to Complete Skin

```bash
hermes config set display.skin slate     # cool blue, complete status bar — good for dark terminals
hermes config set display.skin daylight  # light mode, for bright/white terminal backgrounds
```

## Light Mode Auto-Detection
Hermes queries terminal background color via OSC 11 and auto-remaps "near-white" skin
colors (e.g. `#FFF8DC` banner_text) to darker equivalents readable on cream backgrounds.
Override the detection:
```bash
export HERMES_TUI_THEME=dark    # force dark mode remapping off
export HERMES_TUI_THEME=light   # force light mode remapping on
```

## Config Structure in ~/.hermes/config.yaml
```yaml
display:
  skin: default
  skin_overrides:
    colors:
      status_bar_text: "#C0C0C0"
      status_bar_strong: "#FFD700"
      # ... etc
```
