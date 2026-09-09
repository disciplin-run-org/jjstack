#!/bin/bash
# settings-lint.sh — lint the LIVE ~/.claude/settings.json against the policy.
#
# The other tests prove the hook decides correctly. This one proves the machine
# is actually running it, which is a different claim and the one that was false
# for months: the gate was installed as a SYMLINK into a working checkout, so
# whatever branch that checkout happened to sit on was the machine-wide
# permission policy, and `git checkout` silently changed it.
#
# It also catches the regression that started all of this: a single Bash ask
# rule reintroduces prompts in every mode, including bypassPermissions, where
# allow rules have no effect at all. `Bash(git push *)` in `ask` is not a
# safety net, it is 183 interruptions a person approves one at a time.
#
# Reads the live file only. Exit 0 = the machine matches the policy.
# Usage: test/settings-lint.sh [path-to-settings.json]
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="${1:-$HOME/.claude/settings.json}"
POLICY="$DIR/hooks/permissions.policy.json"
pass=0; fail=0
ok()  { printf '  \033[92mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[95mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

echo "== settings lint: $SETTINGS =="

if [ ! -f "$SETTINGS" ]; then
  bad "settings file exists"
  echo "  $fail failed"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  bad "jq is available (every check here needs it)"
  echo "  $fail failed"; exit 1
fi
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  bad "settings file is valid JSON"
  echo "  $fail failed"; exit 1
fi

# ── mode ─────────────────────────────────────────────────────────────────────
mode=$(jq -r '.permissions.defaultMode // "unset"' "$SETTINGS")
if [ "$mode" = "bypassPermissions" ]; then
  ok "defaultMode is bypassPermissions"
else
  bad "defaultMode is '$mode', want bypassPermissions"
fi

# ── the rule that reintroduces prompts ───────────────────────────────────────
ask_bash=$(jq -r '[.permissions.ask // [] | .[] | select(startswith("Bash("))] | length' "$SETTINGS")
if [ "$ask_bash" -eq 0 ]; then
  ok "no Bash ask rules (an ask rule prompts in every mode, bypass included)"
else
  bad "$ask_bash Bash ask rule(s) present — each one prompts in every mode:"
  jq -r '.permissions.ask // [] | .[] | select(startswith("Bash(")) | "        " + .' "$SETTINGS"
fi

# ── every deny the policy declares is actually installed ─────────────────────
# DERIVE, DON'T ENUMERATE: the expected set is read from the shipped policy, so
# adding a rule there without installing it fails here rather than passing
# quietly against a copy of the list kept in this file.
POLICY_RESOLVED="$(mktemp)"
trap 'rm -f "$POLICY_RESOLVED"' EXIT
sed "s|{{HOME}}|${HOME#/}|g" "$POLICY" > "$POLICY_RESOLVED"
missing=$(jq -r --slurpfile live "$SETTINGS" '
  [ .permissions.deny[] as $d
    | select( ($live[0].permissions.deny // []) | index($d) | not )
    | $d ] | .[]' "$POLICY_RESOLVED")
if [ -z "$missing" ]; then
  ok "every deny rule in the policy is installed ($(jq '.permissions.deny | length' "$POLICY_RESOLVED") rules)"
else
  bad "deny rules declared by the policy but not installed:"
  # Read line by line: a rule is `Bash(sudo rm *)` and word-splitting it turns
  # one missing rule into three lines of nonsense.
  printf '%s\n' "$missing" | while IFS= read -r rule; do printf '        %s\n' "$rule"; done
fi

# ── the hooks, and how they are installed ────────────────────────────────────
floor_cmd=$(jq -r '[.hooks.PreToolUse // [] | .[] | .hooks[]? | .command]
                   | map(select(test("permission-floor"))) | first // ""' "$SETTINGS")
if [ -n "$floor_cmd" ]; then
  ok "the PreToolUse floor hook is registered"
else
  bad "no PreToolUse hook matching 'permission-floor' is registered"
fi

perm_cmd=$(jq -r '[.hooks.PermissionRequest // [] | .[] | .hooks[]? | .command]
                  | map(select(test("auto-approve-safe"))) | first // ""' "$SETTINGS")
if [ -n "$perm_cmd" ]; then
  ok "the PermissionRequest audit hook is registered"
else
  bad "no PermissionRequest hook matching 'auto-approve-safe' is registered"
fi

for entry in "$floor_cmd" "$perm_cmd"; do
  [ -z "$entry" ] && continue
  path="${entry/#\~/$HOME}"
  name=$(basename "$path")
  if [ ! -e "$path" ]; then
    bad "$name: registered but not present at $path"
  elif [ -L "$path" ]; then
    bad "$name: installed as a SYMLINK ($(readlink "$path")) — the live gate follows that checkout's branch"
  else
    ok "$name: installed as a regular file, not a symlink"
    src="$DIR/hooks/$name"
    if [ -f "$src" ] && ! cmp -s "$src" "$path"; then
      bad "$name: the installed copy differs from this checkout — re-run ./setup"
    elif [ -f "$src" ]; then
      ok "$name: the installed copy matches this checkout"
    fi
  fi
done

# ── the floor hook actually refuses something ────────────────────────────────
# An installed-but-inert hook passes every check above. Fire one shipped
# literal through the INSTALLED copy and require a deny: this is the positive
# control, and it is taken from the fixture file rather than invented here.
if [ -n "$floor_cmd" ]; then
  path="${floor_cmd/#\~/$HOME}"
  probe=$(grep -m1 -P '^deny\tUNBOUNDED\t' "$DIR/test/fixtures/permission-policy.tsv" | cut -f3)
  if [ -z "$probe" ]; then
    bad "no UNBOUNDED fixture to use as a positive control"
  else
    out=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$probe" '$c')" \
          | JJSTACK_FLOOR_LOG=/dev/null python3 "$path" 2>/dev/null)
    if printf '%s' "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
      ok "the installed floor refuses a shipped literal ($probe)"
    else
      bad "the installed floor ALLOWED $probe — it is registered but inert"
    fi
  fi
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
