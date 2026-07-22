#!/bin/bash
# jjstack-gbrain-phi-lib.sh — SINGLE SOURCE OF TRUTH for PHI / sensitive-data
# opt-out logic and dashed-slug → real-cwd resolution, shared across the jjstack
# memory tools: jjstack-memory-bridge, jjstack-memory-to-learnings, and
# jjstack-capture-write. This file exists so the PHI gates NEVER fork — a second
# hand-maintained copy is exactly how a sensitive project slips through.
#
# SOURCED, not executed. It deliberately sets no shell options (no set -e/-u) so
# it cannot alter the caller's behavior. Provides:
#   reconstruct_cwd <dashed-slug>         → real cwd (git-preferring; see below)
#   is_slug_opted_out <slug>              → rc 0 if a PATH marker opts it out
#   project_identity_key <slug>           → normalized git-remote key, or ""
#   is_project_identity_opted_out <slug>  → rc 0 if the remote tier is
#                                           deny/read-only; sets IDENTITY_KEY /
#                                           IDENTITY_TIER for the caller's message
#
# Two independent PHI gates, EITHER of which refuses a shared-index write:
#   Gate 1 (is_slug_opted_out) — a path marker in the slug's memory dir:
#     .no-gbrain file, or `sensitivity: phi` in MEMORY.md or any *.md frontmatter.
#   Gate 2 (is_project_identity_opted_out) — the project's git-remote identity is
#     deny/read-only in gstack-gbrain-repo-policy. Binds every live worktree of
#     the remote, closing the moved/cloned-repo hole a path marker cannot.

# Idempotent source guard.
[ -n "${_JJSTACK_GBRAIN_PHI_LIB:-}" ] && return 0
_JJSTACK_GBRAIN_PHI_LIB=1

: "${MEMORY_ROOT:=$HOME/.claude/projects}"
: "${POLICY_BIN:=$HOME/.claude/skills/gstack/bin/gstack-gbrain-repo-policy}"

# Reverse a dashed project key into a real cwd. Two passes. FIRST a
# git-preferring depth-first search that tries the SHORTEST dash-joined prefix at
# each level and returns the first split consuming all tokens AND landing on a
# git-repo root — this disambiguates an empty flat shadow dir
# (PycharmProjects/disciplin-run-actuatrix, non-git) from the real submodule it
# masks (PycharmProjects/disciplin-run/actuatrix); the old greedy pass took the
# LONGEST prefix and the shadow won. If no git interpretation exists (plain
# non-git dirs), fall back to the greedy longest-prefix descent (original
# behavior). Missing tails are appended verbatim so a vanished project fails the
# caller's [ -d ] test.
_reconstruct_git_search() {
    # DFS over token splits from ($_RC_TOKS,$_RC_N); prints a git-root path + rc 0.
    local path="$1" i="$2"
    if [ "$i" -ge "$_RC_N" ]; then
        local top; top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || return 1
        [ "$top" = "$path" ] && { printf '%s' "$path"; return 0; }
        return 1
    fi
    local acc="" k="$i" hit
    while [ "$k" -lt "$_RC_N" ]; do
        if [ -z "$acc" ]; then acc="${_RC_TOKS[$k]}"; else acc="$acc-${_RC_TOKS[$k]}"; fi
        if [ -d "$path/$acc" ]; then
            hit=$(_reconstruct_git_search "$path/$acc" "$((k+1))") && { printf '%s' "$hit"; return 0; }
        fi
        k=$((k+1))
    done
    return 1
}
reconstruct_cwd() {
    local key="${1#-}"
    local IFS='-'; local toks=($key); IFS=' '
    local n=${#toks[@]} path="" i=0
    # Pass 1 — git-preferring (disambiguates flat shadow dirs from submodules).
    _RC_TOKS=("${toks[@]}"); _RC_N="$n"
    local git_hit; git_hit=$(_reconstruct_git_search "" 0) && { printf '%s' "$git_hit"; return; }
    # Pass 2 — greedy longest-prefix fallback (original behavior; non-git dirs).
    while [ "$i" -lt "$n" ]; do
        local acc="" best="" j="$i" k="$i"
        while [ "$k" -lt "$n" ]; do
            if [ -z "$acc" ]; then acc="${toks[$k]}"; else acc="$acc-${toks[$k]}"; fi
            [ -d "$path/$acc" ] && { best="$acc"; j="$k"; }
            k=$((k+1))
        done
        if [ -z "$best" ]; then
            local rem="${toks[$i]}" m=$((i+1))
            while [ "$m" -lt "$n" ]; do rem="$rem-${toks[$m]}"; m=$((m+1)); done
            path="$path/$rem"; break
        fi
        path="$path/$best"; i=$((j+1))
    done
    printf '%s' "$path"
}

is_slug_opted_out() {
    # Gate 1 — path marker in the slug's own memory dir. Returns 0 (opted out)
    # if any marker is present; the caller MUST refuse the shared-index write.
    local slug="$1"
    local mem_dir="$MEMORY_ROOT/$slug/memory"
    [ ! -d "$mem_dir" ] && return 1

    [ -f "$mem_dir/.no-gbrain" ] && return 0

    if [ -f "$mem_dir/MEMORY.md" ]; then
        grep -qE '^[[:space:]]*sensitivity:[[:space:]]*phi' "$mem_dir/MEMORY.md" 2>/dev/null && return 0
    fi

    grep -lE '^[[:space:]]*sensitivity:[[:space:]]*phi' "$mem_dir"/*.md 2>/dev/null | head -1 | grep -q . && return 0

    return 1
}

# slug → normalized remote identity key, or empty string if unresolvable
# (no live cwd, not a git repo, no origin remote, or policy CLI absent).
project_identity_key() {
    local slug="$1"
    [ -x "$POLICY_BIN" ] || return 0
    local cwd remote
    cwd=$(reconstruct_cwd "$slug")
    [ -d "$cwd" ] || return 0
    remote=$(git -C "$cwd" remote get-url origin 2>/dev/null) || return 0
    [ -n "$remote" ] || return 0
    "$POLICY_BIN" normalize "$remote" 2>/dev/null || return 0
}

# Gate 2 — returns 0 (refuse) if the slug's project identity is opted out of
# gbrain writes via the per-remote registry. Sets IDENTITY_KEY / IDENTITY_TIER.
# Returns 1 (allow) when unresolvable or read-write/unset.
IDENTITY_KEY=""
IDENTITY_TIER=""
is_project_identity_opted_out() {
    local slug="$1"
    IDENTITY_KEY=""; IDENTITY_TIER=""
    [ -x "$POLICY_BIN" ] || return 1
    local key tier
    key=$(project_identity_key "$slug")
    [ -n "$key" ] || return 1
    tier=$("$POLICY_BIN" get "$key" 2>/dev/null) || return 1
    IDENTITY_KEY="$key"; IDENTITY_TIER="$tier"
    case "$tier" in
        deny|read-only) return 0 ;;
        *)              return 1 ;;
    esac
}
