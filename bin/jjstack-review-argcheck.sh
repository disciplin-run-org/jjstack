#!/usr/bin/env bash
# jjstack-review-argcheck.sh — the ONE argument guard the review family shares.
#
# Source it, do not execute it:
#   . "$(dirname "${BASH_SOURCE[0]}")/jjstack-review-argcheck.sh"
#
# WHY THIS IS ONE FILE AND NOT FIVE PATCHES
#
# Every script in this family parsed flags the same way:
#
#     --out) OUT="${2:-}"; shift 2 ;;
#
# and every one of them hung for ever on a value-less trailing flag. bash's
# `shift n` FAILS when n > $# instead of shifting what it can, so `shift 2` on
# a lone trailing `--out` moves nothing at all. `set -e` is deliberately off
# across this family — these tools must reach their own documented exit codes
# rather than dying on the first non-zero — so the enclosing
# `while [ $# -gt 0 ]` loop re-read the same flag until something killed it.
# Measured as rc=124 under `timeout 5` on all five Phase 0 scripts.
#
# A hang is strictly worse than a failure in a review chain. A failure is
# reported and the operator knows which pass died; a hang means the run never
# reports at all, and jjstack-review-preflight is the FIRST command /review
# runs, so the whole flagship pass stalls before it prints anything.
#
# The bug is identical in every script, so the fix is one function, called from
# every value-taking case arm before the shift:
#
#     --out) review_need_value "$1" $# || exit 2; OUT="$2"; shift 2 ;;
#
# `$#` there is the count still on the command line INCLUDING the flag itself,
# so a lone trailing `--out` gives 1 and is refused with the family's usage
# exit code, 2.
#
# No color red anywhere — unreadable on the target terminal.

# shellcheck shell=bash

_ARGCHK_CYA="\033[96m"; _ARGCHK_YEL="\033[33m"; _ARGCHK_RST="\033[0m"

review_need_value() {   # review_need_value FLAG REMAINING_ARGC
  if [ "${2:-0}" -lt 2 ]; then
    echo -e "${_ARGCHK_CYA}error${_ARGCHK_RST} $1 requires a value" >&2
    return 1
  fi
  return 0
}

# --- the shared --base contract ----------------------------------------------
# Three tools take `--base`, and all three used to accept a ref that resolves
# but shares NO ancestry with HEAD. `git merge-base` fails, the fallback pinned
# the base to the ref itself, and the report then printed
#
#   diff scope: working tree vs the merge base of `<ref>` and HEAD
#
# — a scope that does not exist — beside a `diff source:` command that does not
# reproduce it. SKILL.md's Phase 4 pass tells the reviewer to QUOTE that line as
# the map's stated limits, so the false claim propagates into the report
# verbatim. jjstack-review-intent widened the same way: `git log <ref>..HEAD`
# with no common ancestor returns the whole branch.
#
# `--base ""` is the same failure one step earlier: it was silently accepted and
# every pass then fell back to its OWN auto-detected base, so one review ran
# three passes over three different scopes without saying so.
#
# All of it is one contract, checked in one place, BEFORE any artifact is
# written: a base must be non-empty, must resolve, and must share history with
# HEAD. Anything else is a named usage error (exit 2), never a silently
# substituted scope.
review_base_check() {   # review_base_check REPO BASE  -> 0 ok, 1 refused
  local repo="${1:-.}" base="$2"
  if [ -z "$base" ]; then
    echo -e "${_ARGCHK_CYA}error${_ARGCHK_RST} --base was given an empty value" >&2
    echo -e "${_ARGCHK_YEL}hint${_ARGCHK_RST}  drop the flag to auto-detect a base, or name a ref" >&2
    return 1
  fi
  if ! git -C "$repo" rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1; then
    echo -e "${_ARGCHK_CYA}error${_ARGCHK_RST} --base '$base' does not resolve to a commit in $repo" >&2
    echo -e "${_ARGCHK_YEL}hint${_ARGCHK_RST}  check the spelling and that the ref is fetched:" >&2
    echo -e "${_ARGCHK_YEL}hint${_ARGCHK_RST}    git -C '$repo' rev-parse --verify '$base'" >&2
    return 1
  fi
  if ! git -C "$repo" merge-base "$base" HEAD >/dev/null 2>&1; then
    echo -e "${_ARGCHK_CYA}error${_ARGCHK_RST} --base '$base' shares no history with HEAD in $repo" >&2
    echo -e "${_ARGCHK_YEL}hint${_ARGCHK_RST}  there is no merge base, so there is no 'changes since' to review." >&2
    echo -e "${_ARGCHK_YEL}hint${_ARGCHK_RST}  reviewing against it would silently widen the scope to the whole" >&2
    echo -e "${_ARGCHK_YEL}hint${_ARGCHK_RST}  tree. Fetch the real base, or pass --diff-file with the diff you mean." >&2
    return 1
  fi
  return 0
}
