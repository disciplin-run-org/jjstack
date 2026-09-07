#!/bin/bash
# smoke.sh — regression smoke tests for the jjstack memory system.
#
# Deterministic and (almost entirely) side-effect-free: syntax checks, pure
# library functions, and --dry-run paths. The one test that writes does so to a
# throwaway slug and cleans up. Codifies the behaviors verified by hand during
# the 2026-07 memory rebuild so they don't silently regress.
#
# Usage: test/smoke.sh   (exit 0 = all pass, 1 = a failure)
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/bin"; HOOKS="$DIR/hooks"
pass=0; fail=0
ok()   { printf '  \033[92mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[95mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "== 1. syntax =="
for f in "$BIN"/jjstack-memory-bridge "$BIN"/jjstack-memory-to-learnings \
         "$BIN"/jjstack-capture-write "$BIN"/jjstack-capture-flush \
         "$BIN"/jjstack-global-learn "$BIN"/jjstack-gbrain-phi-lib.sh \
         "$BIN"/jjstack-capture-review-refs \
         "$BIN"/jjstack-review-blast-radius "$BIN"/jjstack-review-ledger \
         "$BIN"/jjstack-review-revert-history \
         "$HOOKS"/shared-memory.sh "$HOOKS"/capture-on-end.sh; do
  check "bash -n $(basename "$f")" "bash -n '$f' 2>/dev/null"
done

echo "== 2. PHI lib (pure functions) =="
# Source in a subshell so the lib's globals don't leak into the runner.
( source "$BIN/jjstack-gbrain-phi-lib.sh"
  # reconstruct_cwd must return a non-empty path and prefer a git repo when one exists.
  cwd=$(reconstruct_cwd "-home-jesper-PycharmProjects-jjstack")
  [ "$cwd" = "$DIR" ] || [ -d "$cwd" ]
) && ok "reconstruct_cwd resolves a real path" || bad "reconstruct_cwd resolves a real path"

# is_slug_opted_out true for a fixture memory dir carrying .no-gbrain.
TMPROOT=$(mktemp -d)
mkdir -p "$TMPROOT/-fixture-phi/memory"; : > "$TMPROOT/-fixture-phi/memory/.no-gbrain"
mkdir -p "$TMPROOT/-fixture-clean/memory"; : > "$TMPROOT/-fixture-clean/memory/x.md"
( source "$BIN/jjstack-gbrain-phi-lib.sh"; MEMORY_ROOT="$TMPROOT"
  is_slug_opted_out "-fixture-phi" ) && ok "is_slug_opted_out true with .no-gbrain" || bad "is_slug_opted_out true with .no-gbrain"
( source "$BIN/jjstack-gbrain-phi-lib.sh"; MEMORY_ROOT="$TMPROOT"
  is_slug_opted_out "-fixture-clean" ) && bad "is_slug_opted_out false when clean" || ok "is_slug_opted_out false when clean"
rm -rf "$TMPROOT"

echo "== 3. bridge PHI refusal (exit 4) =="
if [ -d "$HOME/.claude/projects/-home-jesper-PycharmProjects-mychart-sync/memory" ]; then
  "$BIN/jjstack-memory-bridge" --slug -home-jesper-PycharmProjects-mychart-sync --ingest --dry-run >/dev/null 2>&1
  check "mychart-sync bridge exits 4" "[ \$? -eq 4 ]"
else
  echo "  SKIP mychart-sync fixture absent"
fi

echo "== 4. capture-write dry-run (no writes) =="
LESSON='{"type":"feedback","name":"smoke probe","description":"d","body":"b","pattern_key":"smoke-probe","scope":"project","is_rule":false,"confidence":7,"source":"observed"}'
out=$("$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
check "capture-write --dry-run resolves canonical slug" "printf '%s' \"\$out\" | grep -q 'canonical slug:'"
check "capture-write --dry-run makes no write claim" "printf '%s' \"\$out\" | grep -q '\\[dry-run\\]'"

echo "== 5. global-learn dry-run (no writes) =="
out=$("$BIN/jjstack-global-learn" --key smoke-probe --insight "x" --dry-run 2>&1)
check "global-learn --dry-run targets __global__" "printf '%s' \"\$out\" | grep -q '__global__'"
check "global-learn --dry-run targets pan-project/ page" "printf '%s' \"\$out\" | grep -q 'pan-project/'"

echo "== 5b. capture-review-refs (allowlist + exclusions) =="
# /review snapshots gstack's review rubric into the repo so old findings stay
# interpretable after a gstack upgrade rebuilds the global clone. The value is
# entirely in the allowlist: capture the durable docs, never the build
# artifacts. Fixture carries both so the exclusions are actually exercised.
CRR="$(mktemp -d)"
mkdir -p "$CRR/src/specialists" "$CRR/src/sections"
: > "$CRR/src/checklist.md"; : > "$CRR/src/design-checklist.md"
: > "$CRR/src/greptile-triage.md"; : > "$CRR/src/TODOS-format.md"
: > "$CRR/src/SKILL.md"; : > "$CRR/src/SKILL.md.tmpl"
: > "$CRR/src/specialists/security.md"; : > "$CRR/src/specialists/red-team.md"
: > "$CRR/src/sections/review-army.md"; : > "$CRR/src/sections/review-army.md.tmpl"
: > "$CRR/src/sections/manifest.json"
printf '9.9.9.9\n' > "$CRR/VERSION"   # sits beside src/, as gstack's does

"$BIN/jjstack-capture-review-refs" "$CRR/out" --gstack-review-dir "$CRR/src" >/dev/null 2>&1
check "capture-review-refs exits 0" "[ \$? -eq 0 ]"
check "captures checklist.md"            "[ -f '$CRR/out/checklist.md' ]"
check "captures specialists/*.md"        "[ -f '$CRR/out/specialists/red-team.md' ]"
check "captures sections/*.md"           "[ -f '$CRR/out/sections/review-army.md' ]"
check "writes PROVENANCE.md"             "[ -f '$CRR/out/PROVENANCE.md' ]"
check "PROVENANCE stamps gstack version" "grep -q '9.9.9.9' '$CRR/out/PROVENANCE.md'"
# Exclusions — the whole point of an allowlist.
check "excludes procedural SKILL.md"   "[ ! -f '$CRR/out/SKILL.md' ]"
check "excludes .tmpl build artifacts" "! find '$CRR/out' -name '*.tmpl' | grep -q ."
check "excludes manifest.json"         "! find '$CRR/out' -name 'manifest.json' | grep -q ."
# Positive control — an exclusion grep that can never fire looks exactly like a
# clean capture, which is how a broken guard passes for months.
check "tmpl guard actually catches a .tmpl" "find '$CRR/src' -name '*.tmpl' | grep -q ."
# --dry-run must not write.
"$BIN/jjstack-capture-review-refs" "$CRR/out2" --gstack-review-dir "$CRR/src" --dry-run >/dev/null 2>&1
check "--dry-run writes nothing" "[ ! -d '$CRR/out2' ]"
# A missing gstack install is a clean exit 3, not a crash or a silent success.
"$BIN/jjstack-capture-review-refs" "$CRR/out3" --gstack-review-dir "$CRR/nope" >/dev/null 2>&1
check "missing gstack dir exits 3" "[ \$? -eq 3 ]"
rm -rf "$CRR"

echo "== 5c. review-blast-radius (cross-file impact map) =="
# The one Greptile mechanic that survives scrutiny is repo-wide context: a
# diff-only reviewer structurally cannot see the callers of the function the
# diff just changed. Ours is grep, so it is exact and testable — and the value
# is entirely in what it EXCLUDES (the changed files, already under review) and
# what it still finds (everything else, including sibling repos).
BR="$(mktemp -d)"
mkdir -p "$BR/repo/src" "$BR/sibling"
cat > "$BR/repo/src/auth.py" <<'EOF'
def build_token(user, ttl, scope):
    return "t"
EOF
cat > "$BR/repo/src/api.py" <<'EOF'
from auth import build_token
handler = build_token("u", 60, "read")
EOF
cat > "$BR/sibling/consumer.py" <<'EOF'
from auth import build_token
EOF
# Diff file lives OUTSIDE the repo so it cannot pollute its own reference map.
cat > "$BR/change.diff" <<'EOF'
--- a/src/auth.py
+++ b/src/auth.py
@@ -1,4 +1,4 @@
-def build_token(user, ttl):
+def build_token(user, ttl, scope):
-def only_here():
+def only_here_now():
EOF
"$BIN/jjstack-review-blast-radius" --repo "$BR/repo" --diff-file "$BR/change.diff" > "$BR/out.md" 2>/dev/null
check "blast-radius exits 0"            "[ \$? -eq 0 ]"
check "maps the changed symbol"         "grep -q 'build_token' '$BR/out.md'"
check "lists an out-of-diff call site"  "grep -q 'src/api.py:' '$BR/out.md'"
check "reports contained symbols"       "grep -q 'only_here_now' '$BR/out.md'"
check "excludes the already-changed file" "! grep -q 'src/auth.py:' '$BR/out.md'"
# POSITIVE CONTROL — an exclusion grep for something never present passes
# whether or not the exclusion works. The changed file must really hold the
# symbol, or "excluded" only means "was never there".
check "changed-file exclusion had something to exclude" "grep -q 'build_token' '$BR/repo/src/auth.py'"

"$BIN/jjstack-review-blast-radius" --repo "$BR/repo" --diff-file "$BR/change.diff" \
  --also-repo "$BR/sibling" > "$BR/cross.md" 2>/dev/null
check "--also-repo finds sibling-repo callers" "grep -q '(sibling) consumer.py' '$BR/cross.md'"
# POSITIVE CONTROL for the flag itself — the sibling site must be ABSENT without
# it, else the check above would pass on a script that always scans everything.
check "sibling callers absent without --also-repo" "! grep -q 'consumer.py' '$BR/out.md'"

"$BIN/jjstack-review-blast-radius" --repo "$BR/repo" --diff-file "$BR/change.diff" \
  --generic-threshold 1 > "$BR/generic.md" 2>/dev/null
check "generic threshold parks noisy symbols" "grep -q 'Too generic to map' '$BR/generic.md'"

# Extraction must be language-scoped. Caught by dogfooding: a global keyword
# set turned English prose ("a function whose contract…") and shell flag values
# ("--type fixed") into symbols, which buried the real ones under junk. A map
# nobody can read is a map nobody uses.
cat > "$BR/noise.diff" <<'EOF'
--- a/docs/notes.md
+++ b/docs/notes.md
@@ -1,2 +1,2 @@
-the class whose type is unclear
+a function whose contract changed
--- a/run.sh
+++ b/run.sh
@@ -1,2 +1,2 @@
-cmd --type fixed --path lib
+cmd --type dismissed --path lib
EOF
"$BIN/jjstack-review-blast-radius" --repo "$BR/repo" --diff-file "$BR/noise.diff" > "$BR/noise.md" 2>/dev/null
check "prose and shell flag values yield no symbols" "grep -q 'definition symbols extracted: 0' '$BR/noise.md'"
# POSITIVE CONTROL — the bait must really be in the fixture, or "0 symbols"
# just means the diff was empty and the scoping is untested.
check "the noise fixture really contains the bait" \
  "grep -q 'whose' '$BR/noise.diff' && grep -q -- '--type fixed' '$BR/noise.diff'"

"$BIN/jjstack-review-blast-radius" --repo "$BR/repo" --diff-file "$BR/change.diff" --max-refs abc >/dev/null 2>&1
check "non-numeric --max-refs exits 2" "[ \$? -eq 2 ]"
"$BIN/jjstack-review-blast-radius" --repo "$BR/nope" --diff-file "$BR/change.diff" >/dev/null 2>&1
check "unresolvable repo exits 3" "[ \$? -eq 3 ]"
rm -rf "$BR"

echo "== 5d. review-ledger (dismissal memory that demotes, never drops) =="
# Every reviewer people keep using grows a memory of what was waved off. The
# risk is that the memory quietly becomes a suppression list — which is how a
# recall-first reviewer turns into a precision-first one without anyone
# deciding to. These tests pin the three rules that stop that.
LD="$(mktemp -d)/ledger.md"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'bin/*' --category style \
  --note 'house style permits it' --ledger "$LD" >/dev/null 2>&1
check "records a dismissal"              "[ -f '$LD' ]"
"$BIN/jjstack-review-ledger" --match --path 'bin/foo.sh' --category style --ledger "$LD" >/dev/null 2>&1
check "prior dismissal demotes a repeat"  "[ \$? -eq 0 ]"
"$BIN/jjstack-review-ledger" --match --path 'src/foo.py' --category style --ledger "$LD" >/dev/null 2>&1
check "unrelated path does not demote"    "[ \$? -eq 1 ]"

# Rule 1: only dismissals suppress. Suppressing a previously-FIXED issue would
# hide the regression of a bug this repo has already paid for once.
"$BIN/jjstack-review-ledger" --record --type fixed --path 'lib/*' --category performance --ledger "$LD" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'lib/x.py' --category performance --ledger "$LD" >/dev/null 2>&1
check "a FIXED record never suppresses" "[ \$? -eq 1 ]"
# POSITIVE CONTROL — the fixed record must really be on file and really match
# path+category, or the non-suppression proves nothing about the type check.
check "the FIXED record exists and matches path+category" "grep -q 'fixed | lib/\* | performance' '$LD'"

# Rule 2: protected categories never demote, however often they are dismissed.
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category security \
  --note 'looked fine at the time' --ledger "$LD" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category security --ledger "$LD" > "$LD.sec" 2>/dev/null
check "protected category never demotes"        "[ \$? -eq 1 ]"
check "protected match still surfaces the history" "grep -q 'PROTECTED' '$LD.sec'"
# POSITIVE CONTROL — the identical shape in an UNPROTECTED category must demote,
# else "never demotes" could just mean the matcher is broken for every category.
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style --ledger "$LD" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style --ledger "$LD" >/dev/null 2>&1
check "same shape in an unprotected category DOES demote" "[ \$? -eq 0 ]"

# Rule 3: a typo'd category is a suppression that fires on the wrong class.
"$BIN/jjstack-review-ledger" --record --type dismissed --path x --category not-a-category --ledger "$LD" >/dev/null 2>&1
check "unknown category exits 2" "[ \$? -eq 2 ]"
"$BIN/jjstack-review-ledger" --record --type maybe --path x --category style --ledger "$LD" >/dev/null 2>&1
check "unknown type exits 2"     "[ \$? -eq 2 ]"
rm -rf "$(dirname "$LD")"

echo "== 5e. review-revert-history (files that burned us before) =="
# A file that has been reverted is not the same review risk as one that never
# has, and the diff never shows that. git already holds the record.
RH="$(mktemp -d)"
git -C "$RH" init -q >/dev/null 2>&1
git -C "$RH" config user.email smoke@test.local
git -C "$RH" config user.name "Smoke Test"
printf 'a\n' > "$RH/pay.py"
printf 'b\n' > "$RH/calm.py"
git -C "$RH" add -A >/dev/null 2>&1
git -C "$RH" commit -q -m 'feat: initial' >/dev/null 2>&1
printf 'a2\n' > "$RH/pay.py"
git -C "$RH" add -A >/dev/null 2>&1
git -C "$RH" commit -q -m 'Revert "feat: charge the card twice"' >/dev/null 2>&1
printf 'b2\n' > "$RH/calm.py"
git -C "$RH" add -A >/dev/null 2>&1
git -C "$RH" commit -q -m 'docs: tidy the wording' >/dev/null 2>&1
cat > "$RH/d.diff" <<'EOF'
--- a/pay.py
+++ b/pay.py
--- a/calm.py
+++ b/calm.py
EOF
"$BIN/jjstack-review-revert-history" --repo "$RH" --diff-file "$RH/d.diff" > "$RH/out.md" 2>/dev/null
check "revert-history exits 0"             "[ \$? -eq 0 ]"
check "flags a file with revert history"   "grep -q 'pay.py' '$RH/out.md'"
check "does not flag a clean file"         "! grep -q 'calm.py' '$RH/out.md'"
# POSITIVE CONTROL — the clean file must actually have been in the diff, or
# "not flagged" just means "never examined" and the discrimination is fictional.
check "the clean file was really examined" "grep -q 'calm.py' '$RH/d.diff'"
"$BIN/jjstack-review-revert-history" --repo "$RH" --diff-file "$RH/d.diff" --limit x >/dev/null 2>&1
check "non-numeric --limit exits 2" "[ \$? -eq 2 ]"
NOGIT="$(mktemp -d)"
"$BIN/jjstack-review-revert-history" --repo "$NOGIT" --diff-file "$RH/d.diff" >/dev/null 2>&1
check "non-git directory exits 3" "[ \$? -eq 3 ]"
rm -rf "$RH" "$NOGIT"

echo
if [ "$fail" -eq 0 ]; then printf '\033[92mALL %d PASS\033[0m\n' "$pass"; exit 0
else printf '\033[95m%d FAIL\033[0m, %d pass\n' "$fail" "$pass"; exit 1; fi
