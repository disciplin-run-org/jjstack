#!/bin/bash

# Usage cache: how often to refresh from the API (seconds)
# 300s = 5 min — fine since the bar only moves in 10% steps over a 5h window
USAGE_CACHE_TTL=300
USAGE_CACHE_FILE="/tmp/claude-usage-cache.json"
CREDENTIALS_FILE="$HOME/.claude/.credentials.json"

input=$(cat)

# -- Model display name (cyan) --
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')

# -- Effort level (read from settings; NOT exposed via statusline input JSON).
# settings.local.json wins over settings.json. Null/missing → "auto" (the
# Claude Code default — let the model pick per task). --
effort=""
for f in "$HOME/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
    [ -f "$f" ] || continue
    val=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
        effort="$val"
        break
    fi
done
[ -z "$effort" ] && effort="auto"

# -- Current folder (basename of cwd) --
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
folder=$(basename "$cwd")

# -- Git branch and state --
git_part=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    state=""
    [ "$staged" -gt 0 ]    && state="${state}+${staged} "
    [ "$modified" -gt 0 ]  && state="${state}~${modified} "
    [ "$untracked" -gt 0 ] && state="${state}?${untracked} "
    state="${state% }"

    [ -z "$state" ] && state="clean"
    git_part="${branch} ${state}"
fi

# Helper: label-inside background-colored bar, percentage after
# The label sits centered; filled portion (left) = bg color, unfilled (right) = dim
create_progress_bar() {
    local pct=$1
    local label=$2
    local pct_int=$(echo "$pct" | awk '{printf "%d", $1}')

    # Background colors: green <70%, yellow 70-89%, red >=90%
    local bg fg
    if   [ "$pct_int" -ge 90 ]; then bg="\033[41m"; fg="\033[97m"   # red bg, bright white
    elif [ "$pct_int" -ge 70 ]; then bg="\033[43m"; fg="\033[30m"   # yellow bg, black
    else                              bg="\033[42m"; fg="\033[30m"   # green bg, black
    fi

    # Padded string: " label " — this is what gets rendered inside the bar
    local padded=" ${label} "
    local total_width=${#padded}

    # How many characters get the filled (bg) treatment
    local filled_chars=$(echo "$pct_int $total_width" | awk '{
        f = int($1/100*$2 + 0.5)
        if (f > $2) f = $2
        print f
    }')

    # Build bar char by char using bash substring ${str:pos:1}
    local bar_str=""
    local i
    for (( i=0; i<total_width; i++ )); do
        local ch="${padded:$i:1}"
        if [ "$i" -lt "$filled_chars" ]; then
            bar_str="${bar_str}${bg}${fg}${ch}\033[0m"
        else
            bar_str="${bar_str}\033[2m${ch}\033[0m"
        fi
    done

    echo -e "${bar_str} ${pct_int}%"
}

# -- Context bar --
context_bar=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
    context_bar=$(create_progress_bar "$used_pct" "context")
fi

# -- Auth mode detection: OAuth (Claude Max/Pro) vs API key (pay-per-token).
# OAuth users get rate-limited on a 5h window (show utilization %).
# API-key users pay per token (show session dollar spend).
# The two are mutually exclusive — pick one, render accordingly. --
AUTH_MODE="api_key"
if [ -f "$CREDENTIALS_FILE" ] && jq -e '.claudeAiOauth.accessToken' "$CREDENTIALS_FILE" >/dev/null 2>&1; then
    AUTH_MODE="oauth"
fi

# -- Trailing segment: usage bar (OAuth) or cost label (API key) --
trailing_segment=""

if [ "$AUTH_MODE" = "oauth" ]; then
    # OAuth path: 5-hour utilization from Anthropic API (cached)
    usage_pct=0

    get_usage_from_api() {
        python3 - "$CREDENTIALS_FILE" <<'PYEOF'
import sys, json, urllib.request, urllib.error

creds_file = sys.argv[1]
try:
    with open(creds_file) as f:
        creds = json.load(f)
    token = creds["claudeAiOauth"]["accessToken"]

    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
            "User-Agent": "claude-code/2.1.81",
            "Accept": "application/json",
        }
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read())
        print(json.dumps(data))
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    }

    # Check cache freshness — never block the statusline waiting for the API.
    cache_valid=false
    if [ -f "$USAGE_CACHE_FILE" ]; then
        cache_age=$(( $(date +%s) - $(date -r "$USAGE_CACHE_FILE" +%s 2>/dev/null || echo 0) ))
        [ "$cache_age" -lt "$USAGE_CACHE_TTL" ] && cache_valid=true
    fi

    if [ "$cache_valid" = false ]; then
        ( get_usage_from_api > "${USAGE_CACHE_FILE}.tmp" 2>/dev/null \
            && mv "${USAGE_CACHE_FILE}.tmp" "$USAGE_CACHE_FILE" ) &
        disown
    fi

    if [ -f "$USAGE_CACHE_FILE" ]; then
        usage_pct=$(jq -r '.five_hour.utilization // 0' "$USAGE_CACHE_FILE" 2>/dev/null | awk '{printf "%d", $1}')
    fi

    [ -z "$usage_pct" ] && usage_pct=0
    trailing_segment=$(create_progress_bar "$usage_pct" "usage")

else
    # API-key path: session dollar spend from statusline input JSON.
    # Thresholds: <$1 green, $1-5 yellow, >=$5 red. Bar label shows amount.
    cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
    [ -z "$cost_usd" ] && cost_usd=0

    # Format to 2 decimals (awk handles scientific-notation + missing values)
    cost_str=$(awk -v c="$cost_usd" 'BEGIN{printf "$%.2f", c+0}')

    # Color by magnitude (5 and 1 USD thresholds)
    cost_cmp=$(awk -v c="$cost_usd" 'BEGIN{if ((c+0)>=5) print 2; else if ((c+0)>=1) print 1; else print 0}')
    case "$cost_cmp" in
        2) cost_color="\033[95m" ;;  # bright magenta >= $5 (avoid red on black)
        1) cost_color="\033[93m" ;;  # bright yellow  >= $1
        *) cost_color="\033[92m" ;;  # bright green   < $1
    esac

    trailing_segment="${cost_color}${cost_str}\033[0m"
fi

# -- Assemble --
SEP="\033[2m | \033[0m"
CYAN="\033[36m"
RESET="\033[0m"

# Effort suffix: dim dot + color-coded level, attached to model with no pipe
effort_part=""
if [ -n "$effort" ]; then
    case "$effort" in
        high)   ecolor="\033[95m" ;;  # bright magenta (avoid red on black)
        medium) ecolor="\033[93m" ;;  # bright yellow
        low)    ecolor="\033[92m" ;;  # bright green
        xhigh)  ecolor="\033[96m" ;;  # bright cyan
        auto)   ecolor="\033[2m"  ;;  # dim (neutral default)
        *)      ecolor="\033[2m"  ;;  # dim (unknown)
    esac
    effort_part=" \033[2m·\033[0m${ecolor}${effort}${RESET}"
fi

line="${CYAN}${model}${RESET}${effort_part}${SEP}${folder}"
[ -n "$git_part" ]   && line="${line}${SEP}${git_part}"
[ -n "$context_bar" ] && line="${line}${SEP}${context_bar}"
[ -n "$trailing_segment" ] && line="${line}${SEP}${trailing_segment}"

echo -e "$line"
