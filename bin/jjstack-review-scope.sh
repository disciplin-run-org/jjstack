#!/usr/bin/env bash
# jjstack-review-scope.sh — THE ONE definition of "this glob names a place".
#
# Every review memory store keys on a glob, and every one of them has to answer
# the same question before it acts: does this pattern name a PLACE in the code,
# or is it a blanket wearing a pattern's clothes? That question was answered
# three times, differently, and the ladder inverted:
#
#   -calibration   key = a global PATTERN CLASS  -> may only RANK      no guard
#   -ledger        key = path glob + category    -> may DEMOTE         semantic
#   -baseline      key = one finding INSTANCE    -> may SUPPRESS       spelling
#
# The rung permitted to SUPPRESS ran the spelling test the ledger's own header
# calls broken, so `*[a-z]*` validated `ok` on the baseline and took a P0 out of
# the active set. The weaker rung was hardened and the stronger one was not.
#
# There is one guard now, and it lives here. Not one rule written twice: one
# implementation, called by both rungs, so the ordering property is structural —
# the strongest rung cannot carry a weaker guard than the weakest rung, because
# there is only one guard to carry.
#
# ---------------------------------------------------------------------------
# THE RULE, in one sentence, in two halves:
#
#   A glob names a place when it carries at least one discriminating character
#   AND it matches at most half of the repository's tracked files.
#
# The first half is decidable with no corpus at all: a pattern built only from
# `*`, `?` and `/` has nothing in it that could pick one path over another, so it
# is a blanket wherever it is written and however it got there — including `/`
# and `?`, which match nothing and are therefore not decisions about a place
# either.
#
# The second half is the one that matters, and it is MEASURED, never spelled.
# Stripping `*?/` catches `*` and `*/*` and waves through `*[a-z]*`, `[a-z]*`,
# `*.*`, `[!q]*`, `*[[:alpha:]]*` and every other spelling nobody happened to
# list; adding those five to the strip set only moves the hole one spelling
# further along, because the next spelling nobody thought of still wins. So the
# pattern is run against the repository's own files and judged on what it
# MATCHES. A glob that matches more than half of a real repository is not a
# decision about a place in it, whatever alphabet it is written in.
#
# ---------------------------------------------------------------------------
# THE CORPUS IS DERIVED, not invented. The first version of the measured rule
# shipped with ten fictional paths hard-coded in the implementation, and the test
# that measured it re-declared the same ten — so the guard was only ever checked
# against its own fixture, and any spelling the fixture did not anticipate was
# free. The corpus is now `git ls-files`, in this order:
#
#   1. $JJSTACK_REVIEW_CORPUS, a file of one path per line (tests, and anyone
#      who needs to ask the question about a tree that is not checked out);
#   2. the tracked files of the repository the STORE belongs to — the right
#      answer, because breadth is a property of a glob AND a repository, not of
#      the glob alone;
#   3. the tracked files of the jjstack checkout these tools live in, when the
#      store's repo cannot be enumerated (a scratch directory, an export). Still
#      a real repository, never a list someone typed;
#   4. a filesystem walk of that checkout, if git is unavailable.
#
# With no corpus at all the answer is NOT "narrow": breadth cannot be certified
# against nothing, so the caller is told (exit 3) rather than handed a pass.
#
# ---------------------------------------------------------------------------
# Source it as a library:
#
#   . "$(dirname "$0")/jjstack-review-scope.sh"
#   scope_names_a_place "$PATTERN" "$REPO"   # 0 = a place, 1 = a blanket
#   scope_blanket_why   "$PATTERN" "$REPO"   # the reason, for the error message
#
# ...or run it, which is how the Python rung asks the same question of the same
# code rather than reimplementing it in a second matcher:
#
#   jjstack-review-scope.sh --corpus  [--repo DIR]        the corpus, one per line
#   jjstack-review-scope.sh --judge   [--repo DIR]        patterns on stdin ->
#                                     "place|blanket<TAB>matched<TAB>total<TAB>why<TAB>pattern"
#   jjstack-review-scope.sh --explain PATTERN [--repo DIR]
#
# Exit: 0 ok (or, for --explain, a place), 1 --explain judged a blanket,
#       2 usage error, 3 no corpus could be derived.
#
# No color red anywhere — unreadable on the target terminal.

# shellcheck shell=bash

_SCOPE_YEL="\033[33m"; _SCOPE_CYA="\033[96m"; _SCOPE_RST="\033[0m"

# The declared threshold, stated once. A glob matching MORE THAN HALF of the
# repository's tracked files says nothing about where the finding is.
SCOPE_BLANKET_NUM=1
SCOPE_BLANKET_DEN=2

_SCOPE_CORPUS=""        # newline separated, cached per (process, repo)
_SCOPE_CORPUS_N=0
_SCOPE_CORPUS_KEY="\0"  # the repo the cache was built for; never a valid path
_SCOPE_CORPUS_SRC=""

_scope_self_dir() {
  local src="${BASH_SOURCE[0]}"
  cd -- "$(dirname -- "$src")" >/dev/null 2>&1 && pwd
}

# `git -C <subdir> ls-files` lists only what is UNDER that subdir, so it must be
# handed a worktree root or the corpus silently becomes one directory. That is a
# fail-OPEN error: judged against bin/ alone, `*.*` matches a minority and a
# blanket is certified as a decision. Resolve the root first, every time.
_scope_git_root() {
  git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null
}

# --- the corpus ---------------------------------------------------------------
scope_corpus_load() {   # scope_corpus_load [REPO]
  local repo="${1:-}" out="" here root
  if [ "$repo" = "$_SCOPE_CORPUS_KEY" ] && [ -n "$_SCOPE_CORPUS" ]; then return 0; fi

  if [ -n "${JJSTACK_REVIEW_CORPUS:-}" ]; then
    if [ ! -r "$JJSTACK_REVIEW_CORPUS" ]; then
      echo -e "${_SCOPE_CYA}error${_SCOPE_RST} JJSTACK_REVIEW_CORPUS is unreadable: $JJSTACK_REVIEW_CORPUS" >&2
      return 3
    fi
    out="$(grep -v '^[[:space:]]*$' "$JJSTACK_REVIEW_CORPUS")"
    _SCOPE_CORPUS_SRC="\$JJSTACK_REVIEW_CORPUS ($JJSTACK_REVIEW_CORPUS)"
  fi
  if [ -z "$out" ] && [ -n "$repo" ] && [ -d "$repo" ]; then
    root="$(_scope_git_root "$repo")"
    if [ -n "$root" ]; then
      out="$(git -C "$root" ls-files 2>/dev/null)"
      [ -n "$out" ] && _SCOPE_CORPUS_SRC="git ls-files in $root"
    fi
  fi
  if [ -z "$out" ]; then
    here="$(_scope_self_dir)"
    if [ -n "$here" ]; then
      root="$(_scope_git_root "$here")"
      if [ -n "$root" ]; then
        out="$(git -C "$root" ls-files 2>/dev/null)"
        [ -n "$out" ] && _SCOPE_CORPUS_SRC="git ls-files in $root"
      fi
      if [ -z "$out" ]; then
        out="$(cd "$here/.." >/dev/null 2>&1 && find . -type f -not -path './.git/*' 2>/dev/null | sed 's|^\./||')"
        [ -n "$out" ] && _SCOPE_CORPUS_SRC="a filesystem walk of ${here%/bin}"
      fi
    fi
  fi
  if [ -z "$out" ]; then
    echo -e "${_SCOPE_CYA}error${_SCOPE_RST} no file corpus could be derived, so no glob's breadth can be" >&2
    echo -e "${_SCOPE_YEL}why${_SCOPE_RST}   certified. Run inside a git checkout, or set JJSTACK_REVIEW_CORPUS" >&2
    echo -e "${_SCOPE_YEL}why${_SCOPE_RST}   to a file listing the repository's paths, one per line." >&2
    return 3
  fi
  _SCOPE_CORPUS="$out"
  _SCOPE_CORPUS_N="$(printf '%s\n' "$out" | grep -c .)"
  _SCOPE_CORPUS_KEY="$repo"
  return 0
}

scope_corpus_source() { printf '%s' "$_SCOPE_CORPUS_SRC"; }

# --- half one: a pattern with nothing discriminating in it --------------------
scope_has_literal() {   # 0 when the pattern carries a character that could pick
  case "$(printf '%s' "${1:-}" | tr -d '*?/')" in
    '') return 1 ;;
  esac
  return 0
}

# --- half two: what the pattern actually MATCHES ------------------------------
scope_matched() {   # scope_matched PATTERN [REPO] -> prints "matched total"
  local pat="${1:-}" repo="${2:-}" p n=0
  scope_corpus_load "$repo" || return 3
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # shellcheck disable=SC2254  # the glob is the point
    case "$p" in
      $pat) n=$((n + 1)) ;;
    esac
  done <<< "$_SCOPE_CORPUS"
  printf '%s %s' "$n" "$_SCOPE_CORPUS_N"
}

# --- the rule -----------------------------------------------------------------
scope_names_a_place() {   # scope_names_a_place PATTERN [REPO]
  local pat="${1:-}" repo="${2:-}" m
  scope_has_literal "$pat" || return 1
  m="$(scope_matched "$pat" "$repo")" || return 3
  [ $(( ${m%% *} * SCOPE_BLANKET_DEN )) -le $(( ${m##* } * SCOPE_BLANKET_NUM )) ]
}

scope_blanket_why() {   # the reason, in the caller's own error message
  local pat="${1:-}" repo="${2:-}" m
  if ! scope_has_literal "$pat"; then
    printf 'it is built only from %s, so it has no character that could pick one path over another' "'*', '?' and '/'"
    return 0
  fi
  m="$(scope_matched "$pat" "$repo")" || return 3
  printf 'it matches %s of the %s files in the repository — more than half, so it names no place in it' \
    "${m%% *}" "${m##* }"
}

# --- executable mode ----------------------------------------------------------
_scope_main() {
  local mode="" repo="" pat="" line m verdict why
  while [ $# -gt 0 ]; do
    case "$1" in
      --corpus)  mode=corpus; shift ;;
      --judge)   mode=judge;  shift ;;
      --explain) mode=explain
                 [ $# -ge 2 ] || { echo -e "${_SCOPE_CYA}error${_SCOPE_RST} --explain needs a PATTERN" >&2; return 2; }
                 pat="$2"; shift 2 ;;
      --repo)    [ $# -ge 2 ] || { echo -e "${_SCOPE_CYA}error${_SCOPE_RST} --repo needs a DIR" >&2; return 2; }
                 repo="$2"; shift 2 ;;
      -h|--help)
        awk 'NR == 1 && /^#!/ { next }
             /^#/                { sub(/^# ?/, ""); print; next }
             { exit }' "${BASH_SOURCE[0]}"
        return 0 ;;
      *) echo -e "${_SCOPE_CYA}error${_SCOPE_RST} unexpected arg: $1" >&2; return 2 ;;
    esac
  done
  case "$mode" in
    corpus)
      scope_corpus_load "$repo" || return 3
      printf '%s\n' "$_SCOPE_CORPUS" ;;
    judge)
      scope_corpus_load "$repo" || return 3
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        if scope_names_a_place "$line" "$repo"; then verdict=place; why="-"
        else verdict=blanket; why="$(scope_blanket_why "$line" "$repo")"; fi
        m="$(scope_matched "$line" "$repo")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$verdict" "${m%% *}" "${m##* }" "$why" "$line"
      done ;;
    explain)
      scope_corpus_load "$repo" || return 3
      if scope_names_a_place "$pat" "$repo"; then
        m="$(scope_matched "$pat" "$repo")"
        echo "place   '$pat' matches ${m%% *} of ${m##* } files ($(scope_corpus_source))"
        return 0
      fi
      echo "blanket '$pat' — $(scope_blanket_why "$pat" "$repo")"
      return 1 ;;
    *) echo -e "${_SCOPE_CYA}error${_SCOPE_RST} one of --corpus, --judge, --explain is required" >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  _scope_main "$@"
  exit $?
fi
