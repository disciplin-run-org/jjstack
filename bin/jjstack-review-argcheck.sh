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

_ARGCHK_CYA="\033[96m"; _ARGCHK_RST="\033[0m"

review_need_value() {   # review_need_value FLAG REMAINING_ARGC
  if [ "${2:-0}" -lt 2 ]; then
    echo -e "${_ARGCHK_CYA}error${_ARGCHK_RST} $1 requires a value" >&2
    return 1
  fi
  return 0
}

# show_help — print the file's own header block as help.
#
# Every script in this family hand-kept a `sed -n 'A,Bp'` range, and four of
# five had already drifted: one printed `set -uo pipefail` as help text,
# another cut its re-entrancy contract mid-sentence. The header is delimited by
# the shebang and the first non-comment line, so read THAT rather than a number
# somebody has to remember to update.
show_help() {   # show_help FILE
  sed -e '1d' "$1" | sed -n '/^[^#]/q;p' | sed 's/^# \{0,1\}//'
}
