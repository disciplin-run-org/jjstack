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
         "$BIN"/jjstack-review-dep-inventory "$BIN"/jjstack-review-blast-radius \
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

echo "== 5c. review-dep-inventory (manifest parsing + vendored-tree exclusion) =="
# /review Phase 4.5b checks stale-API findings against the versions the repo
# ACTUALLY pins, instead of against the model's training-era memory of a library.
# That only works if the parse is right and vendored trees stay out — a
# node_modules manifest would bury the repo's own declarations under thousands
# of foreign ones.
DEP="$(mktemp -d)"
mkdir -p "$DEP/node_modules/evil"
cat > "$DEP/package.json" <<'EOF'
{ "name": "fixture",
  "dependencies": { "react": "^18.2.0", "zod": "3.22.4" },
  "devDependencies": { "vitest": "~1.0.0" } }
EOF
cat > "$DEP/requirements.txt" <<'EOF'
# a comment
fastapi==0.110.1
requests[security]~=2.31.0
bare-package
EOF
cat > "$DEP/go.mod" <<'EOF'
module example.com/fixture
require (
	github.com/stretchr/testify v1.9.0
)
EOF
cat > "$DEP/Cargo.toml" <<'EOF'
[dependencies]
serde = "1.0.197"
tokio = { version = "1.37.0", features = ["full"] }
EOF
cat > "$DEP/node_modules/evil/package.json" <<'EOF'
{ "dependencies": { "should-not-appear": "9.9.9" } }
EOF

# Assertions read a FILE, never `printf ... | grep -q`: under `set -o pipefail`
# a `grep -q` that exits on its first match can leave the pipeline carrying
# printf's SIGPIPE status, which makes the check fail at random. Same reason the
# 5d block below writes its output to a file.
DEPOUT="$(mktemp)"
"$BIN/jjstack-review-dep-inventory" "$DEP" --tsv > "$DEPOUT" 2>/dev/null
check "dep-inventory parses npm version"   "grep -q '^npm	react	\\^18.2.0' '$DEPOUT'"
check "dep-inventory parses pypi ==pin"    "grep -q '^pypi	fastapi	0.110.1' '$DEPOUT'"
check "dep-inventory strips pypi extras"   "grep -q '^pypi	requests	2.31.0' '$DEPOUT'"
check "dep-inventory marks unpinned as *"  "grep -q '^pypi	bare-package	\\*' '$DEPOUT'"
check "dep-inventory parses go.mod"        "grep -q '^go	github.com/stretchr/testify	v1.9.0' '$DEPOUT'"
check "dep-inventory parses cargo inline table" "grep -q '^cargo	tokio	1.37.0' '$DEPOUT'"
# The exclusion that keeps the inventory readable.
check "dep-inventory excludes node_modules" "! grep -q 'should-not-appear' '$DEPOUT'"
# Positive control — an exclusion assertion whose fixture never contained the
# excluded thing passes forever while the prune silently rots.
check "node_modules fixture really holds a manifest to exclude" \
      "grep -q 'should-not-appear' '$DEP/node_modules/evil/package.json'"
# No manifests at all is a clean exit 3, not a crash or an empty success.
DEPEMPTY="$(mktemp -d)"
"$BIN/jjstack-review-dep-inventory" "$DEPEMPTY" >/dev/null 2>&1
check "dep-inventory exits 3 with no manifests" "[ \$? -eq 3 ]"
rm -rf "$DEP" "$DEPEMPTY" "$DEPOUT"

echo "== 5d. review-blast-radius (referrers inside vs outside the diff) =="
# /review Phase 4.5a exists for one bug class: the caller that was NOT updated
# when a definition changed. The whole value is the in-diff / NOT-in-diff split,
# so the fixture changes a signature and updates only ONE of two callers.
BR="$(mktemp -d)"
printf 'def calculate_total(items):\n    return sum(items)\n' > "$BR/core.py"
printf 'from core import calculate_total\nprint(calculate_total([1]))\n' > "$BR/caller_untouched.py"
printf 'from core import calculate_total\nprint(calculate_total([2]))\n' > "$BR/caller_touched.py"
git -C "$BR" init -q 2>/dev/null
git -C "$BR" config user.email t@t.t
git -C "$BR" config user.name t
git -C "$BR" add -A 2>/dev/null
git -C "$BR" commit -qm base 2>/dev/null
# Signature change; caller_touched is updated with it, caller_untouched is not.
printf 'def calculate_total(items, tax):\n    return sum(items) * tax\n' > "$BR/core.py"
printf 'from core import calculate_total\nprint(calculate_total([2], 1.1))\n' > "$BR/caller_touched.py"

BROUT="$(mktemp)"
"$BIN/jjstack-review-blast-radius" --repo "$BR" --tsv > "$BROUT" 2>/dev/null
check "blast-radius exits 0" "[ \$? -eq 0 ]"
check "blast-radius finds the changed definition" "grep -q '^calculate_total	' '$BROUT'"
# The finding that matters: the caller nobody updated.
check "blast-radius flags the un-updated caller as NOT-in-diff" \
      "grep -q '^calculate_total	NOT-in-diff	caller_untouched.py' '$BROUT'"
# Positive control — if the classifier labelled EVERY referrer NOT-in-diff the
# assertion above would still pass while the split was meaningless. This proves
# the in-diff branch actually fires.
check "blast-radius classifies the updated caller as in-diff" \
      "grep -q '^calculate_total	in-diff	caller_touched.py' '$BROUT'"
# A non-git directory is a clean exit 3, not a crash.
BRPLAIN="$(mktemp -d)"
"$BIN/jjstack-review-blast-radius" --repo "$BRPLAIN" >/dev/null 2>&1
check "blast-radius exits 3 outside a git repo" "[ \$? -eq 3 ]"
rm -rf "$BR" "$BRPLAIN" "$BROUT"

echo
if [ "$fail" -eq 0 ]; then printf '\033[92mALL %d PASS\033[0m\n' "$pass"; exit 0
else printf '\033[95m%d FAIL\033[0m, %d pass\n' "$fail" "$pass"; exit 1; fi
