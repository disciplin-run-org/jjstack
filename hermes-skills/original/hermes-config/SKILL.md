---
name: hermes-config
description: "Hermes CLI configuration: skins, colors, display overrides, and UI troubleshooting."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, config, skin, colors, terminal, UI, troubleshooting]
---

# Hermes Configuration & UI Customization

Use this skill when the user wants to change Hermes's appearance, fix broken colors, switch
themes, or troubleshoot the terminal UI.

## Config Commands

```bash
hermes config show                          # show all current config
hermes config set <key> <value>             # set a dotted key
hermes config path                          # show config file path (~/.hermes/config.yaml)
hermes config edit                          # open in $EDITOR
```

Note: `hermes config get` does NOT exist — use `show` and grep.

## Skin / Color System

Hermes uses a skin engine (`hermes_cli/skin_engine.py`). The active skin is set by
`display.skin` in config. Skins can be overridden key-by-key with `display.skin_overrides`.

### Builtin Skins (as of v0.18.2)

| Name | Description |
|------|-------------|
| `default` | Classic gold/kawaii — missing status bar text colors (see Pitfalls) |
| `ares` | Crimson and bronze |
| `mono` | Monochrome |
| `slate` | Cool blue, developer-focused — complete status bar color set |
| `daylight` | Light mode, bright terminal |
| `warm-lightmode` | Warm light mode, dark brown/gold text |
| `poseidon` | Ocean theme |
| `sisyphus` | — |
| `charizard` | — |

Switch skin:
```bash
hermes config set display.skin slate
```

### Available Color Keys

```
banner_border, banner_title, banner_accent, banner_dim, banner_text
ui_accent, ui_label, ui_ok, ui_error, ui_warn
prompt, input_rule
response_border
status_bar_bg, status_bar_text, status_bar_strong, status_bar_dim
status_bar_good, status_bar_warn, status_bar_bad, status_bar_critical
session_label, session_border
```

### Override Individual Colors

```bash
hermes config set display.skin_overrides.colors.<key> "#RRGGBB"
```

Changes take effect on next session start.

## Light/Dark Mode

Hermes auto-detects terminal background via OSC 11 query and remaps "near-white" colors
to darker equivalents in light mode. Override:

```bash
export HERMES_TUI_THEME=dark    # force dark mode
export HERMES_TUI_THEME=light   # force light mode
```

## References

- `references/hermes-skin-color-debugging.md` — step-by-step fix for unreadable status bar text

## Pitfalls

### Default skin has no status bar text colors
The builtin `default` skin defines `status_bar_bg: #1a1a2e` (dark navy) but omits all
`status_bar_text`, `status_bar_dim`, `status_bar_strong`, etc. On a black terminal the text
becomes dark-grey-on-dark-navy — invisible.

**Fix:** Either switch to `slate` (complete color set) or override the missing keys:

```bash
hermes config set display.skin_overrides.colors.status_bar_text "#C0C0C0"
hermes config set display.skin_overrides.colors.status_bar_strong "#FFD700"
hermes config set display.skin_overrides.colors.status_bar_dim "#8B8682"
hermes config set display.skin_overrides.colors.status_bar_good "#4caf50"
hermes config set display.skin_overrides.colors.status_bar_warn "#ffa726"
hermes config set display.skin_overrides.colors.status_bar_bad "#ef5350"
hermes config set display.skin_overrides.colors.status_bar_critical "#FF5252"
```

### hermes config set does not accept bare hex without quotes
Always quote hex color values: `hermes config set display.skin_overrides.colors.status_bar_text "#C0C0C0"`

### Skin engine source location
`/data/hermes/hermes-agent/hermes_cli/skin_engine.py`
`init_skin_from_config()` reads `display.skin` and `display.skin_overrides` from config at startup.
