#!/usr/bin/env bash
# jjstack-review-vocab.sh — shell reader for the ONE review vocabulary.
#
# This file holds NO vocabulary of its own. It parses bin/jjstack-review-vocab.tsv,
# which is the single definition shared by the run report and all three memory
# stores. If you are tempted to add a reason code here, add it to the TSV instead
# — a second list is exactly the failure this pair of files exists to prevent.
#
# The escalation ladder it enforces:
#
#   scope pattern-class (calibration)  may emit at most  rank
#   scope path-glob     (ledger)       may emit at most  demote
#   scope instance      (baseline)     may emit at most  suppress
#
# The narrower the key, the stronger the verdict. Flatten that and a global
# heuristic can silently suppress a specific P0, which is the whole reason the
# three stores were kept apart.
#
# Source it, do not execute it:
#   . "$(dirname "$0")/jjstack-review-vocab.sh"
#
# Functions:
#   vocab_path                     path to the TSV (honours JJSTACK_REVIEW_VOCAB)
#   vocab_load                     parse the TSV into the arrays below; exit 3 if unreadable
#   vocab_reason_codes             every reason code, space separated
#   vocab_effects                  every effect name, space separated
#   vocab_scopes                   every scope name, space separated
#   vocab_effect_ordinal NAME      integer ordinal, or empty for an unknown effect
#   vocab_scope_max SCOPE          the strongest effect that scope may emit
#   vocab_reason_max CODE          the strongest effect that reason code may carry
#   vocab_is_reason CODE           0 if CODE is in the closed vocabulary
#   vocab_check SCOPE CODE EFFECT  0 if legal; otherwise prints why to stderr and returns 1
#
# No color red anywhere — unreadable on the target terminal.

# shellcheck shell=bash

_VOCAB_YEL="\033[33m"; _VOCAB_CYA="\033[96m"; _VOCAB_RST="\033[0m"

VOCAB_REASONS=""
VOCAB_EFFECTS=""
VOCAB_SCOPES=""
_VOCAB_LOADED=0
declare -A VOCAB_EFFECT_ORD=()
declare -A VOCAB_SCOPE_MAX=()
declare -A VOCAB_REASON_MAX=()

vocab_path() {
  if [ -n "${JJSTACK_REVIEW_VOCAB:-}" ]; then
    printf '%s\n' "$JJSTACK_REVIEW_VOCAB"
    return 0
  fi
  printf '%s\n' "${BASH_SOURCE[0]%/*}/jjstack-review-vocab.tsv"
}

vocab_load() {
  [ "$_VOCAB_LOADED" -eq 1 ] && return 0
  local f kind name value rest
  f="$(vocab_path)"
  if [ ! -f "$f" ]; then
    echo -e "${_VOCAB_CYA}error${_VOCAB_RST} review vocabulary not found: $f" >&2
    return 3
  fi
  while IFS=$'\t' read -r kind name value rest; do
    case "$kind" in
      ''|\#*) continue ;;
    esac
    [ -n "$name" ] || continue
    case "$kind" in
      effect) VOCAB_EFFECT_ORD["$name"]="$value"; VOCAB_EFFECTS="$VOCAB_EFFECTS $name" ;;
      scope)  VOCAB_SCOPE_MAX["$name"]="$value";  VOCAB_SCOPES="$VOCAB_SCOPES $name" ;;
      reason) VOCAB_REASON_MAX["$name"]="$value"; VOCAB_REASONS="$VOCAB_REASONS $name" ;;
    esac
  done < "$f"
  VOCAB_EFFECTS="${VOCAB_EFFECTS# }"
  VOCAB_SCOPES="${VOCAB_SCOPES# }"
  VOCAB_REASONS="${VOCAB_REASONS# }"
  if [ -z "$VOCAB_REASONS" ] || [ -z "$VOCAB_EFFECTS" ] || [ -z "$VOCAB_SCOPES" ]; then
    echo -e "${_VOCAB_CYA}error${_VOCAB_RST} review vocabulary is empty or malformed: $f" >&2
    return 3
  fi
  _VOCAB_LOADED=1
  return 0
}

vocab_reason_codes() { vocab_load || return 3; printf '%s\n' "$VOCAB_REASONS"; }
vocab_effects()      { vocab_load || return 3; printf '%s\n' "$VOCAB_EFFECTS"; }
vocab_scopes()       { vocab_load || return 3; printf '%s\n' "$VOCAB_SCOPES"; }

vocab_effect_ordinal() {
  vocab_load || return 3
  printf '%s\n' "${VOCAB_EFFECT_ORD[$1]:-}"
}

vocab_scope_max() {
  vocab_load || return 3
  printf '%s\n' "${VOCAB_SCOPE_MAX[$1]:-}"
}

vocab_reason_max() {
  vocab_load || return 3
  printf '%s\n' "${VOCAB_REASON_MAX[$1]:-}"
}

vocab_is_reason() {
  vocab_load || return 3
  [ -n "${VOCAB_REASON_MAX[$1]:-}" ]
}

# The ladder check. Returns 0 only when EFFECT is within BOTH ceilings: the one
# the scope allows and the one the reason code allows.
vocab_check() {
  local scope="$1" code="$2" effect="$3"
  vocab_load || return 3
  local scope_max reason_max o_eff o_scope o_reason
  scope_max="${VOCAB_SCOPE_MAX[$scope]:-}"
  if [ -z "$scope_max" ]; then
    echo -e "${_VOCAB_CYA}error${_VOCAB_RST} unknown scope '$scope' (want: $VOCAB_SCOPES)" >&2
    return 1
  fi
  o_eff="${VOCAB_EFFECT_ORD[$effect]:-}"
  if [ -z "$o_eff" ]; then
    echo -e "${_VOCAB_CYA}error${_VOCAB_RST} unknown effect '$effect' (want: $VOCAB_EFFECTS)" >&2
    return 1
  fi
  o_scope="${VOCAB_EFFECT_ORD[$scope_max]:-0}"
  if [ "$o_eff" -gt "$o_scope" ]; then
    echo -e "${_VOCAB_CYA}error${_VOCAB_RST} scope '$scope' may emit at most '$scope_max', not '$effect'." >&2
    echo -e "${_VOCAB_YEL}why${_VOCAB_RST}   the narrower the key, the stronger the verdict. A '$scope' record" >&2
    echo -e "${_VOCAB_YEL}why${_VOCAB_RST}   keys on a class, so it may not act on one specific finding." >&2
    return 1
  fi
  if [ "$code" != "-" ]; then
    reason_max="${VOCAB_REASON_MAX[$code]:-}"
    if [ -z "$reason_max" ]; then
      echo -e "${_VOCAB_CYA}error${_VOCAB_RST} unknown reason code '$code'" >&2
      echo -e "${_VOCAB_YEL}valid${_VOCAB_RST} $VOCAB_REASONS" >&2
      return 1
    fi
    o_reason="${VOCAB_EFFECT_ORD[$reason_max]:-0}"
    if [ "$o_eff" -gt "$o_reason" ]; then
      echo -e "${_VOCAB_CYA}error${_VOCAB_RST} reason '$code' may carry at most '$reason_max', not '$effect'." >&2
      return 1
    fi
  fi
  return 0
}
