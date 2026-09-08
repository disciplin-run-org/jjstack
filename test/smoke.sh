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
         "$BIN"/jjstack-capture-review-refs "$BIN"/jjstack-number-lines \
         "$BIN"/jjstack-review-preflight "$BIN"/jjstack-review-tooling-sweep \
         "$BIN"/jjstack-review-blast-radius "$BIN"/jjstack-review-intent \
         "$BIN"/jjstack-review-prior-dismissals \
         "$BIN"/jjstack-review-sweep "$BIN"/jjstack-review-autofix-diff \
         "$BIN"/jjstack-review-calibration "$BIN"/jjstack-review-triage \
         "$BIN"/jjstack-review-ledger "$BIN"/jjstack-review-revert-history \
         "$HOOKS"/shared-memory.sh "$HOOKS"/capture-on-end.sh; do
  check "bash -n $(basename "$f")" "bash -n '$f' 2>/dev/null"
done
# ast.parse, not py_compile: py_compile drops a __pycache__ into bin/.
for f in "$BIN"/jjstack-review-normalize "$BIN"/jjstack-review-baseline; do
  check "python -n $(basename "$f")" \
    "python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' '$f' 2>/dev/null"
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
# JJSTACK_CAPTURE_NO_GBRAIN pins this section to Layer A. Without it, --dry-run
# queries a LIVE gbrain index under an 8s timeout: the answer changes as the
# index grows and the latency is not ours to control, so these assertions were
# neither deterministic nor fast — contradicting this file's own header. Layer B
# has its own coverage below; it is pinned here, not skipped.
LESSON='{"type":"feedback","name":"smoke probe","description":"d","body":"b","pattern_key":"smoke-probe","scope":"project","is_rule":false,"confidence":7,"source":"observed"}'
out=$(JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
# Herestrings, not `printf | grep`: a pipeline under `pipefail` reports the
# left-hand status too, so an assertion could fail for reasons unrelated to the
# match. A herestring has no pipeline and no such ambiguity.
check "capture-write --dry-run resolves canonical slug" "grep -q 'canonical slug:' <<<\"\$out\""
check "capture-write --dry-run marks output dry-run" "grep -q '\\[dry-run\\]' <<<\"\$out\""
check "capture-write --dry-run names WHY the layer was skipped" "grep -q 'gbrain dedup:  not-run:pinned' <<<\"\$out\""

# Positive control: without the pin Layer B must actually run, or the pin above
# proves nothing and we have quietly stopped testing the real path. Uses a STUB
# gbrain on PATH rather than the real one — the control stays hermetic, instant,
# and works on a machine with no gbrain installed.
STUB=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' > "$STUB/gbrain"; chmod +x "$STUB/gbrain"
out_live=$(PATH="$STUB:$PATH" "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
check "gbrain layer runs when not pinned (control)" "grep -q 'gbrain dedup:  ran-clean' <<<\"\$out_live\""
# And the pin must beat an available gbrain, not merely an absent one.
out_pin=$(PATH="$STUB:$PATH" JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
check "pin overrides an available gbrain" "grep -q 'gbrain dedup:  not-run:pinned' <<<\"\$out_pin\""

# A HUNG gbrain must not report as a clean run. This is the failure the whole
# observability exists to expose: timeout kills the query, stderr is discarded,
# the result is empty — which is indistinguishable from "no duplicate found"
# unless the state says so. Stub sleeps past the 8s deadline.
# The deadline is configurable so this costs 1s, not 8 — a test that makes the
# suite slow is a test people stop running.
HANG=$(mktemp -d)
printf '#!/bin/sh\nsleep 30\n' > "$HANG/gbrain"; chmod +x "$HANG/gbrain"
out_hang=$(PATH="$HANG:$PATH" JJSTACK_CAPTURE_GBRAIN_TIMEOUT=1 "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
check "a timed-out gbrain query reports ran-timeout" "grep -q 'gbrain dedup:  ran-timeout' <<<\"\$out_hang\""
check "a timed-out query is NOT reported as clean"   "! grep -q 'gbrain dedup:  ran-clean' <<<\"\$out_hang\""

# A timeout is only ONE way the query fails. A corrupt or unreadable index (1),
# timeout(1) itself failing on a bad deadline (125), a non-executable (126) or a
# vanished binary (127) all produce the same empty stdout on the same
# stderr-discarded path — so believing any of them is the identical bug, and the
# fix that disbelieved only 124 left the rest reporting ran-clean.
ERR=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$ERR/gbrain"; chmod +x "$ERR/gbrain"
out_err=$(PATH="$ERR:$PATH" "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
check "a failing gbrain query reports ran-error"   "grep -q 'gbrain dedup:  ran-error:1' <<<\"\$out_err\""
check "a failing query is NOT reported as clean"   "! grep -q 'gbrain dedup:  ran-clean' <<<\"\$out_err\""
# Positive control on the CODE, not just the state: a different failure must
# report a different rc, or the state could be a constant that happens to match.
printf '#!/bin/sh\nexit 3\n' > "$ERR/gbrain"
out_err3=$(PATH="$ERR:$PATH" "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)
check "the failing query's exit code is carried through (control)" "grep -q 'gbrain dedup:  ran-error:3' <<<\"\$out_err3\""
# Positive control on the WHOLE branch: the exit-0 stub above still reaches
# ran-clean, so ran-error is a discrimination and not a blanket refusal.
check "a clean query still reports ran-clean (control)" "grep -q 'gbrain dedup:  ran-clean' <<<\"\$out_live\""
rm -rf "$HANG" "$STUB" "$ERR"

# The section is named "no writes" but only ever checked stdout. Assert the
# actual claim: a --dry-run leaves the memory dir untouched.
#
# The watched dir must be DERIVED, not baked. An earlier version hardcoded
# "$HOME/.claude/projects/-home-jesper-PycharmProjects-jjstack/memory" while the
# script derives its dir from the --cwd it is given. Run from any other checkout
# the two never coincide, so `ls | wc -l` counted an unrelated directory
# identically before and after and the guard could not fail; run from that one
# clone it read the user's LIVE memory store, which the capture-on-end worker
# writes to concurrently, so it flaked. A guard that cannot fire, in the section
# whose whole point is hermeticity.
#
# Fixed by giving the test its own project AND its own HOME, and computing the
# watched path with the script's own cwd→dashed transform.
FIXH=$(mktemp -d); FIXP=$(mktemp -d)
FIXMEM="$FIXH/.claude/projects/$(printf '%s' "$FIXP" | sed 's|/|-|g')/memory"
# Mark the fixture project PHI-opted-out. The positive control below performs a
# REAL write; the PHI gate stops it at the native .md, so nothing reaches gstack,
# gbrain, or the user's own stores. Hermetic, and it exercises the real path.
mkdir -p "$FIXMEM"; : > "$FIXMEM/.no-gbrain"
before=$(ls -1 "$FIXMEM" 2>/dev/null | wc -l)
HOME="$FIXH" JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" \
    --cwd "$FIXP" --dry-run --lesson "$LESSON" >/dev/null 2>&1
after=$(ls -1 "$FIXMEM" 2>/dev/null | wc -l)
check "capture-write --dry-run writes no memory file" "[ \"\$before\" = \"\$after\" ]"
# POSITIVE CONTROL: the same call WITHOUT --dry-run must move that count. If it
# does not, the assertion above is watching a directory the script never touches
# and proves nothing — which is exactly how the baked path passed everywhere.
HOME="$FIXH" JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" \
    --cwd "$FIXP" --lesson "$LESSON" >/dev/null 2>&1
wrote=$(ls -1 "$FIXMEM" 2>/dev/null | wc -l)
check "the no-write guard watches the dir the script writes (control)" "[ \"\$wrote\" -gt \"\$after\" ]"
rm -rf "$FIXH" "$FIXP"

echo "== 5. global-learn dry-run (no writes) =="
out=$("$BIN/jjstack-global-learn" --key smoke-probe --insight "x" --dry-run 2>&1)
check "global-learn --dry-run targets __global__" "grep -q '__global__' <<<\"\$out\""
check "global-learn --dry-run targets pan-project/ page" "grep -q 'pan-project/' <<<\"\$out\""

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

echo "== 5c. review pre-flight evidence pack =="
# /review Phase 0 runs deterministic pre-passes BEFORE any AI pass. Each is
# tested against a throwaway git repo built to contain the exact defect the
# pre-pass exists to catch — a public symbol renamed in the diff while a file
# OUTSIDE the diff still calls it. Nothing here touches the jjstack repo: the
# sweep would otherwise re-enter this very script.
# The sweep's re-entrancy guard reads this from the environment, and this suite
# IS a test runner the sweep can invoke — so it can arrive already set. Clear it
# so every assertion below tests the script, not the ambient environment; the
# guard's own test sets it explicitly.
unset JJSTACK_REVIEW_PREFLIGHT
PF="$(mktemp -d)"; FX="$PF/fx"
mkdir -p "$FX/lib" "$FX/test"
git -C "$FX" init -q -b main 2>/dev/null
git -C "$FX" config user.email t@t; git -C "$FX" config user.name T
printf '#!/usr/bin/env bash\ncompute_total() { echo 1; }\nMAX_RETRIES=3\n' > "$FX/lib/core.sh"
printf '#!/usr/bin/env bash\n. lib/core.sh\ncompute_total\necho "$MAX_RETRIES"\necho DocOnlySymbol CommentOnlySymbol\n' > "$FX/consumer.sh"
printf '# Fixture docs\n' > "$FX/README.md"
printf '#!/usr/bin/env bash\necho fixture-ok\nexit 0\n' > "$FX/test/smoke.sh"
chmod +x "$FX/test/smoke.sh"
git -C "$FX" add -A >/dev/null 2>&1; git -C "$FX" commit -qm "feat: seed" >/dev/null 2>&1
# The change under review: rename the public symbol, bump the constant, and
# add two decoys — a "class" in a doc file and a "type" inside a comment. Both
# name things consumer.sh mentions, so a broken noise filter shows up as a
# spurious entry rather than as silence.
printf '#!/usr/bin/env bash\n# type CommentOnlySymbol\ncompute_grand_total() { echo 1; }\nMAX_RETRIES=5\n' > "$FX/lib/core.sh"
printf '# Fixture docs\n\nclass DocOnlySymbol\n' > "$FX/README.md"
git -C "$FX" add -A >/dev/null 2>&1
git -C "$FX" commit -qm "refactor: rename compute_total, fixes #42" >/dev/null 2>&1

# --- pre-pass 2: blast radius (the defect diff-only review cannot see) ---
"$BIN/jjstack-review-blast-radius" --out "$PF/br" --repo "$FX" --base HEAD~1 >/dev/null 2>&1
check "blast-radius exits 0" "[ \$? -eq 0 ]"
check "blast-radius finds the renamed symbol's outside caller" \
      "grep -q 'compute_total' '$PF/br/blast-radius.md' && grep -q 'consumer.sh' '$PF/br/blast-radius.md'"
check "blast-radius finds the changed constant's outside use" \
      "grep -q 'MAX_RETRIES' '$PF/br/blast-radius.md'"
# The new definition lives only in the diff, so it must NOT be listed as an
# outside reference. Positive control for the changed-file exclusion.
check "blast-radius excludes references inside the diff" \
      "! grep -q 'lib/core.sh:' '$PF/br/blast-radius.md'"
# Noise filters: prose files declare no symbols, and neither do comments.
# Without these, ordinary English becomes a "symbol" matching half the repo and
# buries the real call sites.
check "blast-radius ignores symbols declared in doc files" \
      "! grep -q 'DocOnlySymbol' '$PF/br/blast-radius.md'"
check "blast-radius ignores symbols declared in comments" \
      "! grep -q 'CommentOnlySymbol' '$PF/br/blast-radius.md'"
# Positive control — both guards would also 'pass' if the decoys were never in
# the diff, or had no outside reference to be reported against.
check "decoy symbols really are in the diff" \
      "git -C '$FX' diff HEAD~1 | grep -q 'class DocOnlySymbol' && git -C '$FX' diff HEAD~1 | grep -q 'type CommentOnlySymbol'"
check "decoy symbols really are referenced outside the diff" \
      "grep -q 'DocOnlySymbol CommentOnlySymbol' '$FX/consumer.sh'"
# --- the enclosing-definition case (gstack's "enum completeness") ---
# The highest-value out-of-diff defect, and the one all three competing
# implementations missed identically: a change INSIDE a class/enum body while
# the `class X:` line itself is untouched. The enclosing type's contract just
# changed for every outside user, but no definition LINE was added, so
# pattern-on-changed-lines extraction sees nothing. gstack names this the one
# category that "requires reading code OUTSIDE the diff".
ENC="$(mktemp -d)"
git -C "$ENC" init -q; git -C "$ENC" config user.email f@x.dev; git -C "$ENC" config user.name F
printf 'class OrderStatus:\n    OPEN = "open"\n' > "$ENC/core.py"
printf 'from core import OrderStatus\ndef report(o):\n    return o == OrderStatus.OPEN\n' > "$ENC/reporting.py"
git -C "$ENC" add -A; git -C "$ENC" commit -qm base
printf 'class OrderStatus:\n    OPEN = "open"\n    CLOSED = "closed"\n' > "$ENC/core.py"
git -C "$ENC" add -A; git -C "$ENC" commit -qm "add enum member"
"$BIN/jjstack-review-blast-radius" --out "$ENC/out" --repo "$ENC" --base HEAD~1 >/dev/null 2>&1
check "blast-radius maps a change inside a class body to the class" \
      "grep -q 'OrderStatus' '$ENC/out/blast-radius.md'"
check "blast-radius names the out-of-diff user of that class" \
      "grep -q 'reporting.py' '$ENC/out/blast-radius.md'"
# Positive control — the enclosing definition line must genuinely be UNCHANGED,
# or the test passes for the wrong reason (an ordinary added-definition case).
check "the class definition line is untouched in the diff" \
      "! git -C '$ENC' diff HEAD~1 | grep -qE '^[+-]class OrderStatus'"
check "the changed line really is inside the class body" \
      "git -C '$ENC' diff HEAD~1 | grep -qE '^\\+    CLOSED'"
rm -rf "$ENC"

"$BIN/jjstack-review-blast-radius" --out "$PF/br2" --repo "$FX" --base HEAD --dry-run >/dev/null 2>&1
check "blast-radius --dry-run writes nothing" "[ ! -d '$PF/br2' ]"
"$BIN/jjstack-review-blast-radius" --out "$PF/br3" --repo "$PF" >/dev/null 2>&1
check "blast-radius outside a git repo exits 3" "[ \$? -eq 3 ]"

# --- pre-pass 1 + 5: tooling sweep and test baseline ---
"$BIN/jjstack-review-tooling-sweep" --out "$PF/sw" --repo "$FX" >/dev/null 2>&1
check "tooling-sweep exits 0 when tools pass" "[ \$? -eq 0 ]"
check "tooling-sweep detects and runs the test suite" \
      "grep -q 'test/smoke.sh' '$PF/sw/tooling-results.md'"
check "tooling-sweep writes a test baseline" "[ -f '$PF/sw/test-baseline.md' ]"
check "baseline records the green state" "grep -q 'result:  pass' '$PF/sw/test-baseline.md'"
# The load-bearing rule: a category is COVERED only if its tool RAN and PASSED.
check "exclusions mark the passing test suite COVERED" \
      "grep -q 'COVERED.*test suite' '$PF/sw/exclusions.md'"
check "exclusions keep the absent typechecker IN SCOPE" \
      "grep -q 'IN SCOPE — no passing typechecker' '$PF/sw/exclusions.md'"
# A parse sweep is not a style linter; claiming otherwise silences a category
# nothing checked.
check "parse sweep does not claim style coverage" \
      "grep -q 'NOT a style linter' '$PF/sw/exclusions.md'"
# A FAILING tool must never yield a COVERED claim — this is the guard that
# stops the review going quiet about the thing that is actually broken.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/sw2" --repo "$FX" \
   --typecheck none --lint none --test 'echo boom >&2; exit 7' >/dev/null 2>&1
check "tooling-sweep exits 1 when a tool fails" "[ \$? -eq 1 ]"
check "a failing tool is reported as a real finding" \
      "grep -q 'test FAILED' '$PF/sw2/tooling-results.md' && grep -q 'boom' '$PF/sw2/tooling-results.md'"
check "a failing tool excludes NOTHING" \
      "! grep -q '^## COVERED' '$PF/sw2/exclusions.md'"
check "baseline records the RED state" "grep -q 'baseline is RED' '$PF/sw2/test-baseline.md'"
# Positive control — "no COVERED anywhere" would also pass if the script never
# wrote COVERED at all. Prove the string CAN appear.
check "COVERED guard can actually fire" "grep -q '^## COVERED' '$PF/sw/exclusions.md'"
# Re-entrancy: a project whose test command invokes /review must not recurse.
JJSTACK_REVIEW_PREFLIGHT=1 "$BIN/jjstack-review-tooling-sweep" \
  --out "$PF/sw3" --repo "$FX" --dry-run > "$PF/reentry.out" 2>&1
check "re-entrancy guard suppresses the test suite" \
      "grep -q 're-entrancy guard' '$PF/reentry.out'"
# Positive control — the guard's message would also be absent if the fixture
# simply had no test runner to suppress.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/sw4" --repo "$FX" --dry-run > "$PF/noreentry.out" 2>&1
check "without the guard the fixture DOES detect a test runner" \
      "grep -q 'test:      test/smoke.sh' '$PF/noreentry.out'"
check "tooling-sweep --dry-run writes nothing" "[ ! -d '$PF/sw3' ]"

# --- pre-pass 3: intent gathering ---
"$BIN/jjstack-review-intent" --out "$PF/it" --repo "$FX" --base HEAD~1 >/dev/null 2>&1
check "intent exits 0" "[ \$? -eq 0 ]"
check "intent captures the commit message" \
      "grep -q 'rename compute_total' '$PF/it/intent.md'"
check "intent extracts the referenced issue" "grep -q '#42' '$PF/it/intent.md'"
# No PR here — that must read as 'structurally inapplicable', never as a pass.
check "intent reports a missing PR as inapplicable" \
      "grep -qi 'structurally inapplicable' '$PF/it/intent.md'"

# --- pre-pass 4: prior dismissals ---
# gstack-review-read emits JSONL, then ---CONFIG--- and further sections. Only
# the lines BEFORE the marker are JSONL; the fixture puts a decoy record after
# it so the boundary is actually exercised.
cat > "$PF/reviews.txt" <<'EOF'
{"skill":"review","timestamp":"2026-01-01T00:00:00Z","findings":[{"fingerprint":"lib/core.sh:2:maintainability","severity":"INFORMATIONAL","action":"skipped"},{"fingerprint":"lib/core.sh:3:security","severity":"CRITICAL","action":"fixed"}]}
{"truncated json
{"skill":"review","timestamp":"2026-02-02T00:00:00Z","findings":[{"fingerprint":"consumer.sh:4:performance","severity":"INFORMATIONAL","action":"skipped"}]}
---CONFIG---
false
---WTREE---
{"skill":"review","timestamp":"2026-03-03T00:00:00Z","findings":[{"fingerprint":"DECOY-PAST-MARKER:1:x","severity":"CRITICAL","action":"skipped"}]}
EOF
"$BIN/jjstack-review-prior-dismissals" --out "$PF/pd" --input "$PF/reviews.txt" >/dev/null 2>&1
check "prior-dismissals exits 0" "[ \$? -eq 0 ]"
check "collects skipped fingerprints" \
      "grep -q 'lib/core.sh:2:maintainability' '$PF/pd/prior-dismissals.md'"
check "ignores non-skipped actions" \
      "! grep -q 'lib/core.sh:3:security' '$PF/pd/prior-dismissals.md'"
check "stops at the ---CONFIG--- marker" \
      "! grep -q 'DECOY-PAST-MARKER' '$PF/pd/prior-dismissals.md'"
check "a malformed row is skipped, not fatal" \
      "grep -q 'malformed rows skipped: 1' '$PF/pd/prior-dismissals.md'"
# Positive control — the marker guard would also 'pass' if the parser found
# nothing at all. Prove it really parsed both sides' worth of records.
check "marker guard actually had something to exclude" \
      "grep -q 'DECOY-PAST-MARKER' '$PF/reviews.txt'"
check "parser did find the pre-marker records" \
      "grep -q 'dismissed fingerprints: 2' '$PF/pd/prior-dismissals.md'"
"$BIN/jjstack-review-prior-dismissals" --out "$PF/pd2" --reader "$PF/no-such-reader" >/dev/null 2>&1
check "missing gstack reader exits 3" "[ \$? -eq 3 ]"

# --- orchestrator: the pack is always written, and always says what skipped ---
"$BIN/jjstack-review-preflight" --out "$PF/pack" --repo "$FX" --base HEAD~1 >/dev/null 2>&1
check "preflight exits 0" "[ \$? -eq 0 ]"
check "preflight writes the pack index" "[ -f '$PF/pack/EVIDENCE-PACK.md' ]"
for a in tooling-results.md exclusions.md test-baseline.md blast-radius.md intent.md prior-dismissals.md; do
  check "pack contains $a" "[ -f '$PF/pack/$a' ]"
done
check "pack index lists all five pre-passes" \
      "[ \$(grep -c '^| [1-5] |' '$PF/pack/EVIDENCE-PACK.md') -eq 5 ]"
"$BIN/jjstack-review-preflight" --out "$PF/pack2" --repo "$FX" --dry-run >/dev/null 2>&1
check "preflight --dry-run writes nothing" "[ ! -d '$PF/pack2' ]"

# --- the index must never claim more than its artifacts support -------------
# Every row status used to be derived from the sweep's single aggregate exit
# code. One rc cannot describe three tools: a repo with no tooling got
# "ran — all detected tools passed" and "baseline recorded (green)" above a
# test-baseline.md reading "runner: none / NO baseline exists". The COVERED /
# IN SCOPE mechanism was right all along; the summary over it was lying.
#
# Positive control first: on a fixture that DOES have a green runner the index
# says so. Without this, every "must not say green" assertion below would also
# pass against a script that never emits the word.
check "index says green when a runner really did pass (control)" \
      "grep -q '^| 5 .*baseline recorded (green)' '$PF/pack/EVIDENCE-PACK.md'"
check "that green row is backed by the artifact (control)" \
      "grep -q 'result:  pass' '$PF/pack/test-baseline.md'"

BARE="$PF/bare"; mkdir -p "$BARE"
git -C "$BARE" init -q -b main 2>/dev/null
git -C "$BARE" config user.email t@t; git -C "$BARE" config user.name T
printf 'hello\n' > "$BARE/notes.txt"
git -C "$BARE" add -A >/dev/null 2>&1; git -C "$BARE" commit -qm seed >/dev/null 2>&1
printf 'hello world\n' > "$BARE/notes.txt"
git -C "$BARE" add -A >/dev/null 2>&1; git -C "$BARE" commit -qm edit >/dev/null 2>&1
"$BIN/jjstack-review-preflight" --out "$BARE/pack" --repo "$BARE" --base HEAD~1 >/dev/null 2>&1
check "a repo with no tooling still gets a pack" "[ -f '$BARE/pack/EVIDENCE-PACK.md' ]"
check "index NEVER reports a green baseline that was never recorded" \
      "! grep -q 'baseline recorded (green)' '$BARE/pack/EVIDENCE-PACK.md'"
check "index row 5 names the missing baseline as a gap" \
      "grep -q '^| 5 .*NO baseline exists' '$BARE/pack/EVIDENCE-PACK.md'"
check "index row 1 does not claim tools passed when none ran" \
      "! grep -q '^| 1 .*all detected tools passed' '$BARE/pack/EVIDENCE-PACK.md'"
check "index row 1 says nothing was checked" \
      "grep -q '^| 1 .*NOTHING was checked' '$BARE/pack/EVIDENCE-PACK.md'"
# The invariant itself, asserted as a comparison rather than a string match:
# row 5 may only read "green" when the artifact it points at recorded a pass.
check "index row 5 agrees with test-baseline.md" \
      "grep -q 'result:  pass' '$BARE/pack/test-baseline.md' || ! grep -q '^| 5 .*(green)' '$BARE/pack/EVIDENCE-PACK.md'"
check "the load-bearing exclusions are still correct on a bare repo (control)" \
      "[ \$(grep -c '^## IN SCOPE' '$BARE/pack/exclusions.md') -eq 3 ] && ! grep -q '^## COVERED' '$BARE/pack/exclusions.md'"

# --skip-tests produced the identical false green: the suite was never run, yet
# the index reported a recorded baseline.
"$BIN/jjstack-review-preflight" --out "$PF/pack3" --repo "$FX" --base HEAD~1 --skip-tests >/dev/null 2>&1
check "--skip-tests never reports a recorded green baseline" \
      "! grep -q 'baseline recorded (green)' '$PF/pack3/EVIDENCE-PACK.md'"
check "--skip-tests row 5 says NO baseline exists" \
      "grep -q '^| 5 .*NO baseline exists' '$PF/pack3/EVIDENCE-PACK.md'"
check "--skip-tests baseline artifact agrees" \
      "! grep -q 'result:  pass' '$PF/pack3/test-baseline.md'"
# Positive control — the fixture genuinely HAS a runner, so this is the flag
# suppressing it, not an absent suite.
check "the --skip-tests fixture really has a runner (control)" \
      "grep -q 'test/smoke.sh' '$PF/pack3/tooling-results.md'"

# The rc=1 arm was wrong in the other direction: a typecheck or lint failure
# rendered a GREEN test suite as "baseline recorded (RED: pre-existing
# failures)". A broken shell script fails the parse sweep with no external
# dependency, so this stays hermetic.
RED="$PF/red"; mkdir -p "$RED/test"
git -C "$RED" init -q -b main 2>/dev/null
git -C "$RED" config user.email t@t; git -C "$RED" config user.name T
printf '#!/usr/bin/env bash\necho fixture-ok\nexit 0\n' > "$RED/test/smoke.sh"
chmod +x "$RED/test/smoke.sh"
printf '#!/usr/bin/env bash\nif [ ; then\n' > "$RED/broken.sh"
git -C "$RED" add -A >/dev/null 2>&1; git -C "$RED" commit -qm seed >/dev/null 2>&1
"$BIN/jjstack-review-preflight" --out "$RED/pack" --repo "$RED" --base HEAD >/dev/null 2>&1
check "a lint failure does NOT repaint a green baseline red" \
      "! grep -q '^| 5 .*RED' '$RED/pack/EVIDENCE-PACK.md'"
check "the green baseline survives another tool's failure" \
      "grep -q '^| 5 .*baseline recorded (green)' '$RED/pack/EVIDENCE-PACK.md'"
# Positive control — a tool really did fail in that same run, or row 5 was
# never under pressure and the two assertions above prove nothing.
check "a tool really did fail in that run (control)" \
      "grep -q '^| 1 .*deterministic failures found' '$RED/pack/EVIDENCE-PACK.md'"
check "and the test suite really did pass in it (control)" \
      "grep -q 'result:  pass' '$RED/pack/test-baseline.md'"

# --- could not run is a KNOWN GAP, never a finding --------------------------
# run_tool collapsed every non-zero rc into FAIL(rc=N) under a heading reading
# "real findings, report these" — which SKILL.md tells the reviewer to fold
# into the report as fact, skipping confidence scoring. A missing binary is not
# a finding about the code.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/gap1" --repo "$FX" \
   --typecheck none --lint none --test 'jjstack-no-such-binary-xyz' >/dev/null 2>&1
check "a missing binary is not reported as a real finding" \
      "! grep -q 'test FAILED — real findings' '$PF/gap1/tooling-results.md'"
check "a missing binary is reported as a KNOWN GAP" \
      "grep -q 'test COULD NOT RUN' '$PF/gap1/tooling-results.md'"
check "a tool that could not run excludes NOTHING" \
      "! grep -q '^## COVERED.*test suite' '$PF/gap1/exclusions.md'"
check "a tool that could not run leaves no baseline" \
      "grep -q 'NO baseline' '$PF/gap1/test-baseline.md'"
# A timeout is the same class: the tool was killed, it did not judge the code.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/gap2" --repo "$FX" \
   --typecheck none --lint none --test 'sleep 30' --timeout 1 >/dev/null 2>&1
check "a timed-out tool is a KNOWN GAP, not a finding" \
      "grep -q 'test COULD NOT RUN' '$PF/gap2/tooling-results.md' && ! grep -q 'real findings' '$PF/gap2/tooling-results.md'"
# Positive control — the "real findings" heading must still fire for a tool
# that DID run and DID fail, or the guard above is just suppressing everything.
check "a genuine tool failure is still a real finding (control)" \
      "grep -q 'test FAILED — real findings' '$PF/sw2/tooling-results.md'"

# --- the npm-script probe must not execute repo-controlled JS ---------------
# "$REPO" was interpolated raw into a `node -e` JS string literal, so a path
# component containing  ');  closed the literal and appended attacker JS —
# during plain detection, and even under --dry-run, which promises to run
# nothing. A lone apostrophe in a legitimate directory name silently disabled
# npm-script detection entirely.
INJ="$PF/inj"; mkdir -p "$INJ"
printf 'module.exports={};\n' > "$INJ/evil.js"
EVIL="$INJ/evil');require('fs').writeFileSync(process.env.PWNED,'x');b=('"
mkdir -p "$EVIL"
printf '{"scripts":{"test":"true"}}\n' > "$EVIL/package.json"
# Positive control FIRST: run the OLD interpolation by hand and prove the
# payload is live. Without this, "no marker file" would also pass against a
# payload that never worked.
PWNED="$INJ/pwned" node -e "const p=require('$EVIL/package.json');process.exit(0)" >/dev/null 2>&1
check "the injection payload is genuinely live (control)" "[ -f '$INJ/pwned' ]"
rm -f "$INJ/pwned"
PWNED="$INJ/pwned" "$BIN/jjstack-review-tooling-sweep" \
   --out "$INJ/out" --repo "$EVIL" --dry-run > "$INJ/dry.out" 2>&1
check "the probe executes no JS from the repo path" "[ ! -f '$INJ/pwned' ]"
check "detection still reads the real script list from a hostile path" \
      "grep -q 'test:      npm run --silent test' '$INJ/dry.out'"
check "and does not invent scripts the package.json never declared" \
      "grep -q 'typecheck: <none detected>' '$INJ/dry.out'"
APO="$INJ/jesper's repo"; mkdir -p "$APO"
printf '{"scripts":{"typecheck":"true","lint":"true","test":"true"}}\n' > "$APO/package.json"
"$BIN/jjstack-review-tooling-sweep" --out "$INJ/o2" --repo "$APO" --dry-run > "$INJ/apo.out" 2>&1
check "an apostrophe in a path does not disable npm-script detection" \
      "grep -q 'typecheck: npm run --silent typecheck' '$INJ/apo.out'"
# Positive control — the same package.json in a plain path, so the assertion
# above is about the apostrophe and not about node being absent.
mkdir -p "$INJ/plain"; cp "$APO/package.json" "$INJ/plain/package.json"
"$BIN/jjstack-review-tooling-sweep" --out "$INJ/o3" --repo "$INJ/plain" --dry-run > "$INJ/plain.out" 2>&1
check "the same package.json detects in a plain path (control)" \
      "grep -q 'typecheck: npm run --silent typecheck' '$INJ/plain.out'"

# --- the blast-radius map must see uncommitted work -------------------------
# `git diff BASE...HEAD` sees committed work only, and a three-dot diff with an
# empty result still exits 0 — so the `|| git diff "$BASE"` fallback beside it
# was dead code. The flagship scenario as an UNCOMMITTED edit mapped as
# "Empty diff — nothing to map" while the stale caller sat there.
UNC="$PF/unc"; mkdir -p "$UNC/lib"
git -C "$UNC" init -q -b main 2>/dev/null
git -C "$UNC" config user.email t@t; git -C "$UNC" config user.name T
printf '#!/usr/bin/env bash\ncompute_total() { echo 1; }\n' > "$UNC/lib/core.sh"
printf '#!/usr/bin/env bash\n. lib/core.sh\ncompute_total\n' > "$UNC/consumer.sh"
git -C "$UNC" add -A >/dev/null 2>&1; git -C "$UNC" commit -qm seed >/dev/null 2>&1
printf '#!/usr/bin/env bash\ncompute_grand_total() { echo 1; }\n' > "$UNC/lib/core.sh"
git -C "$UNC" add -A >/dev/null 2>&1
"$BIN/jjstack-review-blast-radius" --out "$UNC/br" --repo "$UNC" --base main >/dev/null 2>&1
check "blast-radius maps a staged-but-uncommitted rename" \
      "grep -q 'compute_total' '$UNC/br/blast-radius.md'"
check "and names its stale out-of-diff caller" \
      "grep -q 'consumer.sh' '$UNC/br/blast-radius.md'"
check "an uncommitted change is not reported as an empty diff" \
      "! grep -q 'Empty diff' '$UNC/br/blast-radius.md'"
check "the report states which diff scope it used" \
      "grep -q 'diff scope:' '$UNC/br/blast-radius.md'"
# Positive control — the work really is uncommitted, so the three-dot diff the
# old code used is genuinely empty and this is not a committed-diff test in
# disguise.
check "the change really is uncommitted (control)" \
      "[ -z \"\$(git -C '$UNC' diff main...HEAD)\" ] && [ -n \"\$(git -C '$UNC' diff main)\" ]"

rm -rf "$PF"
echo "== 5d. number-lines (grounded locations) =="
# A review pass shown bare source has to COUNT to report a line, and that is
# where "real bug, wrong line" false positives come from. Numbering makes the
# location something to copy. The fixture deliberately holds a blank line and
# a final line with no trailing newline — both are where naive numbering slips.
NL="$(mktemp -d)"
printf 'def foo():\n\n    return 1' > "$NL/src.py"   # no trailing newline on purpose
"$BIN/jjstack-number-lines" "$NL/src.py" > "$NL/out.txt" 2>/dev/null; rc=$?
check "number-lines exits 0"          "[ $rc -eq 0 ]"
check "numbers from L1"               "head -1 '$NL/out.txt' | grep -q '^L1: def foo():$'"
check "numbers the blank line too"    "grep -qx 'L2: ' '$NL/out.txt'"
check "keeps unterminated last line"  "grep -q '^L3:     return 1$' '$NL/out.txt'"
check "emits exactly 3 lines"         "[ \"\$(wc -l < '$NL/out.txt')\" -eq 3 ]"
"$BIN/jjstack-number-lines" "$NL/src.py" --start 100 > "$NL/off.txt" 2>/dev/null
check "--start offsets a chunk"       "head -1 '$NL/off.txt' | grep -q '^L100: '"
# Positive control — the blank-line assertion above only means something if the
# fixture actually contains a blank line; a fixture drift would make it vacuous.
check "fixture really has a blank line" "grep -qx '' '$NL/src.py'"
"$BIN/jjstack-number-lines" "$NL/nope.py" >/dev/null 2>&1; rc=$?
check "missing file exits 3"          "[ $rc -eq 3 ]"
"$BIN/jjstack-number-lines" "$NL/src.py" --start abc >/dev/null 2>&1; rc=$?
check "non-numeric --start exits 2"   "[ $rc -eq 2 ]"
# PR #16 review (P2): an unconditional `exit 0` masked awk failure. Reproduced
# by writing to /dev/full — awk fails, output is empty, and the old script
# still exited 0. A lens then reports zero findings on a file it never read,
# which is indistinguishable from a clean file. /dev/full fails for root too,
# so this does not depend on the uid the suite runs as.
check "positive control: /dev/full exists" "[ -c /dev/full ]"
"$BIN/jjstack-number-lines" "$NL/src.py" > /dev/full 2>/dev/null; rc=$?
check "a failed write exits 4, not 0"  "[ $rc -eq 4 ]"
# Positive control — the SAME command to a working sink must still succeed, or
# "exits 4" could just mean the script is broken for every input.
"$BIN/jjstack-number-lines" "$NL/src.py" > /dev/null 2>&1; rc=$?
check "positive control: same command to a good sink exits 0" "[ $rc -eq 0 ]"
# --help is delimited by the first non-comment line, not a hardcoded range, so
# editing the header block above cannot silently truncate it.
check "--help reaches the end of the header" \
  "\"$BIN/jjstack-number-lines\" --help 2>/dev/null | grep -q 'No color red anywhere'"
rm -rf "$NL"

echo "== 5e. review-normalize (finding struct + confidence) =="
# Every finding must arrive as a struct the reader can act on. `remediation`
# is required at EMISSION time precisely because a finding nobody can act on
# is not worth a line in the report.
RN="$(mktemp -d)"
GOOD='{"lens":"security","file":"a.py","start_line":"12","severity":"HIGH","confidence":75,"message":"m","quote":"os.system(x)","explanation":"e","remediation":"r"}'
# Same record, remediation removed — the ONLY difference, so a rejection here
# can only be the remediation guard firing.
NOREM='{"lens":"security","file":"a.py","start_line":"12","severity":"HIGH","confidence":75,"message":"m","quote":"os.system(x)","explanation":"e"}'
printf '%s\n' "$GOOD" > "$RN/good.jsonl"
printf '%s\n' "$NOREM" > "$RN/norem.jsonl"

"$BIN/jjstack-review-normalize" "$RN/good.jsonl" > "$RN/good.out" 2>/dev/null; rc=$?
check "normalize exits 0 on a valid finding" "[ $rc -eq 0 ]"
check "0-100 confidence becomes 0.0-1.0"     "grep -q '\"confidence\": 0.75' '$RN/good.out'"
check "keeps a 0-100 view for the report"    "grep -q '\"confidence_100\": 75' '$RN/good.out'"
check "severity HIGH canonicalizes to P1"    "grep -q '\"severity\": \"P1\"' '$RN/good.out'"
check "start_line coerced to an integer"     "grep -q '\"start_line\": 12' '$RN/good.out'"
# A 0.0-1.0 emitter must survive untouched, and an over-range one must clamp.
printf '%s\n' "${GOOD/\"confidence\":75/\"confidence\":0.75}" > "$RN/frac.jsonl"
"$BIN/jjstack-review-normalize" "$RN/frac.jsonl" 2>/dev/null > "$RN/frac.out"
check "0.0-1.0 confidence passes through"    "grep -q '\"confidence\": 0.75' '$RN/frac.out'"
printf '%s\n' "${GOOD/\"confidence\":75/\"confidence\":150}" > "$RN/over.jsonl"
"$BIN/jjstack-review-normalize" "$RN/over.jsonl" 2>/dev/null > "$RN/over.out"
check "out-of-range confidence clamps to 1.0" "grep -q '\"confidence\": 1.0' '$RN/over.out'"

"$BIN/jjstack-review-normalize" "$RN/norem.jsonl" > "$RN/norem.out" 2>"$RN/norem.err"; rc=$?
check "missing remediation exits 1"     "[ $rc -eq 1 ]"
check "malformed finding not emitted"   "[ ! -s '$RN/norem.out' ]"
check "malformed finding is REPORTED"   "grep -q 'missing required field(s): remediation' '$RN/norem.err'"
# Positive control — prove the guard is the remediation check and not some
# other rejection: the identical record WITH remediation must pass.
"$BIN/jjstack-review-normalize" "$RN/good.jsonl" >/dev/null 2>&1; rc=$?
check "positive control: same record + remediation passes" "[ $rc -eq 0 ]"
printf 'not json at all\n' > "$RN/junk.jsonl"
"$BIN/jjstack-review-normalize" "$RN/junk.jsonl" >/dev/null 2>&1; rc=$?
check "unparseable line exits 1, not a crash" "[ $rc -eq 1 ]"

# --- PR #16 review (P0): one bad field discarded the ENTIRE findings set ---
# `float(None)` raises TypeError, only ValueError was caught, and valid findings
# were printed only AFTER the loop — so a single `"confidence": null` emptied
# stdout, never wrote the malformed file, and exited 1: the same code as "some
# malformed". Two real P0s vanished with no record. The fixture puts the bad
# line BETWEEN two good ones so buffering-vs-streaming is actually exercised.
P0A='{"lens":"security","file":"a.py","start_line":12,"severity":"P0","confidence":0.9,"message":"valid p0 one","quote":"os.system(x)","explanation":"e","remediation":"r"}'
P0B='{"lens":"perf","file":"c.py","start_line":5,"severity":"P0","confidence":0.8,"message":"valid p0 two","quote":"q2","explanation":"e","remediation":"r"}'
NULLCONF='{"lens":"security","file":"b.py","start_line":3,"severity":"P0","confidence":null,"message":"null conf","quote":"q","explanation":"e","remediation":"r"}'
printf '%s\n%s\n%s\n' "$P0A" "$NULLCONF" "$P0B" > "$RN/nullconf.jsonl"
"$BIN/jjstack-review-normalize" "$RN/nullconf.jsonl" \
  --invalid-out "$RN/nullconf.bad.jsonl" > "$RN/nullconf.out" 2>/dev/null; rc=$?
check "a null confidence does not crash the run"   "[ $rc -eq 1 ]"
check "the surrounding valid P0s survive"          "[ \"\$(wc -l < '$RN/nullconf.out')\" -eq 2 ]"
check "the P0 BEFORE the bad line is emitted"      "grep -q 'valid p0 one' '$RN/nullconf.out'"
check "the P0 AFTER the bad line is emitted"       "grep -q 'valid p0 two' '$RN/nullconf.out'"
check "the malformed finding IS recorded"          "[ -s '$RN/nullconf.bad.jsonl' ]"
check "the malformed record names the bad field"   "grep -q 'confidence' '$RN/nullconf.bad.jsonl'"
# Positive control — the identical three lines with a real confidence must all
# pass, or "2 survived" could mean the guard rejects far more than null.
printf '%s\n%s\n%s\n' "$P0A" "${NULLCONF/\"confidence\":null/\"confidence\":0.5}" "$P0B" \
  > "$RN/nullconf.ok.jsonl"
"$BIN/jjstack-review-normalize" "$RN/nullconf.ok.jsonl" > "$RN/nullconf.ok.out" 2>/dev/null; rc=$?
check "positive control: same 3 lines with a number all pass" \
  "[ $rc -eq 0 ] && [ \"\$(wc -l < '$RN/nullconf.ok.out')\" -eq 3 ]"
# The other JSON shapes float() rejects with TypeError, not ValueError. Assert
# on the RECORD, not just rc=1: a crash also exits 1, so an rc-only check would
# read a total loss as a clean rejection — the exact confusion this P0 was.
for bad in '[]' '{}' 'true' '"high"'; do
  printf '%s\n' "${P0A/\"confidence\":0.9/\"confidence\":$bad}" > "$RN/conf.jsonl"
  rm -f "$RN/conf.bad.jsonl"
  "$BIN/jjstack-review-normalize" "$RN/conf.jsonl" --invalid-out "$RN/conf.bad.jsonl" \
    > "$RN/conf.out" 2>/dev/null; rc=$?
  check "confidence $bad is rejected AND recorded" \
    "[ $rc -eq 1 ] && [ ! -s '$RN/conf.out' ] && [ -s '$RN/conf.bad.jsonl' ]"
done

# PR #16 review (P2): the non-blank guard only inspected `str`, so a null quote
# and an empty-list remediation walked through the schema gate this file exists
# to enforce — a P1 reaching the report with an uncheckable location.
printf '%s\n' "${GOOD/\"quote\":\"os.system(x)\"/\"quote\":null}" > "$RN/nullquote.jsonl"
"$BIN/jjstack-review-normalize" "$RN/nullquote.jsonl" > "$RN/nullquote.out" 2>"$RN/nullquote.err"; rc=$?
check "a null quote is rejected"        "[ $rc -eq 1 ] && [ ! -s '$RN/nullquote.out' ]"
check "the null quote is REPORTED"      "grep -q 'quote' '$RN/nullquote.err'"
printf '%s\n' "${GOOD/\"remediation\":\"r\"/\"remediation\":[]}" > "$RN/emptyrem.jsonl"
"$BIN/jjstack-review-normalize" "$RN/emptyrem.jsonl" > "$RN/emptyrem.out" 2>/dev/null; rc=$?
check "an empty-list remediation is rejected" "[ $rc -eq 1 ] && [ ! -s '$RN/emptyrem.out' ]"
# Positive control — a numeric 0 is CONTENT, not blankness. If the guard were
# written as a plain falsiness test it would reject this, and the two checks
# above would be proving nothing about null in particular.
printf '%s\n' "${GOOD/\"confidence\":75/\"confidence\":0}" > "$RN/zeroconf.jsonl"
"$BIN/jjstack-review-normalize" "$RN/zeroconf.jsonl" > "$RN/zeroconf.out" 2>/dev/null; rc=$?
check "positive control: a zero confidence is content, not blank" \
  "[ $rc -eq 0 ] && grep -q '\"confidence\": 0.0' '$RN/zeroconf.out'"

# PR #16 review (P0, second half): a crash must NOT share exit 1 with "some
# malformed", or the caller reads total loss as partial success. Load the
# script as a module and force an exception the per-finding handler does not
# catch — the only way to reach the last-resort guard from outside.
cat > "$RN/internal.py" <<'PYEOF'
import importlib.machinery, importlib.util, sys

loader = importlib.machinery.SourceFileLoader("jjnorm", sys.argv[1])
spec = importlib.util.spec_from_loader("jjnorm", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)


def boom(_obj):
    raise RuntimeError("injected internal failure")


if "--patch" in sys.argv:
    mod.normalize_finding = boom
sys.exit(mod.main([sys.argv[2]]))
PYEOF
python3 "$RN/internal.py" "$BIN/jjstack-review-normalize" "$RN/good.jsonl" --patch \
  >/dev/null 2>&1; rc=$?
check "an internal error exits 3, never 1"  "[ $rc -eq 3 ]"
# Positive control — the same harness without the injected fault must exit 0,
# proving 3 came from the fault and not from the loading shim.
python3 "$RN/internal.py" "$BIN/jjstack-review-normalize" "$RN/good.jsonl" \
  >/dev/null 2>&1; rc=$?
check "positive control: unpatched harness exits 0" "[ $rc -eq 0 ]"
rm -rf "$RN"

echo "== 5f. review-baseline (suppression, never deletion) =="
# The baseline is how a re-review surfaces only NEW issues without losing the
# old ones. Two mechanisms with deliberately different aging: brittle
# fingerprints (edit the source, the finding comes back) and drift-tolerant
# rules (survive rewording, which is why they need a stated reason).
RB="$(mktemp -d)"
F1='{"lens":"security","file":"a.py","start_line":12,"severity":"P1","confidence":0.75,"message":"shell injection","quote":"os.system(x)","explanation":"e","remediation":"r"}'
F2='{"lens":"perf","file":"b.py","start_line":3,"severity":"P2","confidence":0.4,"message":"n+1 query","quote":"for r in rows: get(r)","explanation":"e2","remediation":"r2"}'
printf '%s\n%s\n' "$F1" "$F2" > "$RB/findings.jsonl"

# Mandatory reason — an unexplained suppression is indistinguishable from a bug.
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" -o "$RB/noreason.json" >/dev/null 2>&1; rc=$?
check "generate without --reason exits 2" "[ $rc -eq 2 ]"
check "generate without --reason writes nothing" "[ ! -f '$RB/noreason.json' ]"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "accepted in triage" \
  -o "$RB/bl.json" >/dev/null 2>&1; rc=$?
check "generate with --reason exits 0" "[ $rc -eq 0 ]"
check "baseline records both fingerprints" "[ \"\$(grep -c 'sha256:' '$RB/bl.json')\" -eq 2 ]"
check "every fingerprint carries a reason" "[ \"\$(grep -c '\"reason\"' '$RB/bl.json')\" -eq 2 ]"

"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/bl.json" \
  > "$RB/all.out" 2>/dev/null; rc=$?
check "apply exits 0 when nothing is active" "[ $rc -eq 0 ]"
# The core property: suppressed is NOT deleted. Both findings still present.
check "suppressed findings stay in the output" "[ \"\$(wc -l < '$RB/all.out')\" -eq 2 ]"
check "suppression is auditable (reason shown)" "grep -q 'accepted in triage' '$RB/all.out'"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/bl.json" \
  --active-only > "$RB/active.out" 2>/dev/null
check "--active-only shows just the new stuff" "[ ! -s '$RB/active.out' ]"

# Fingerprints are brittle ON PURPOSE: edit the flagged source, get it back.
printf '%s\n%s\n' "${F1/os.system(x)/os.system(y)}" "$F2" > "$RB/edited.jsonl"
"$BIN/jjstack-review-baseline" apply "$RB/edited.jsonl" --baseline "$RB/bl.json" \
  --active-only > "$RB/edited.out" 2>/dev/null; rc=$?
check "editing the quoted line reactivates it" "[ \"\$(wc -l < '$RB/edited.out')\" -eq 1 ]"
check "a reactivated finding exits 1"          "[ $rc -eq 1 ]"
# ...but an unrelated edit ABOVE the finding only shifts start_line, and must not.
printf '%s\n%s\n' "${F1/\"start_line\":12/\"start_line\":40}" "$F2" > "$RB/shifted.jsonl"
"$BIN/jjstack-review-baseline" apply "$RB/shifted.jsonl" --baseline "$RB/bl.json" \
  --active-only > "$RB/shifted.out" 2>/dev/null
check "a pure line shift does NOT reactivate"  "[ ! -s '$RB/shifted.out' ]"

# Drift-tolerant glob rules.
printf '{"version":2,"jjstack_version":"x","rules":[{"id":"per*","reason":"policy: perf lens is advisory here"}],"fingerprints":[]}\n' > "$RB/rules.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/rules.json" \
  --active-only > "$RB/rules.out" 2>/dev/null; rc=$?
check "glob rule suppresses its lens"       "[ \"\$(wc -l < '$RB/rules.out')\" -eq 1 ]"
check "glob rule leaves other lenses active" "grep -q 'shell injection' '$RB/rules.out'"
# Positive control — the rule guard can actually reject. A malformed-baseline
# check that never fires looks exactly like a clean baseline.
printf '{"version":2,"rules":[{"id":"per*"}],"fingerprints":[]}\n' > "$RB/noreason-rule.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/noreason-rule.json" >/dev/null 2>&1; rc=$?
check "rule without a reason exits 2" "[ $rc -eq 2 ]"
printf '{"version":2,"rules":[{"reason":"because"}],"fingerprints":[]}\n' > "$RB/catchall.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/catchall.json" >/dev/null 2>&1; rc=$?
check "reason-only rule exits 2" "[ $rc -eq 2 ]"
# PR #16 review (P1): the guard above only asked whether a field was PRESENT
# and non-empty, so a universal glob sailed through and muted the whole repo at
# exit 0 — the posture table then read "nothing above P3" and emitted APPROVE.
# Reproduced with {"path":"*"}: 0 active, 2 suppressed, rc=0. `file` and
# `rule_id` are aliases `rule_matches` honours, so they are covered too.
for wk in path file id rule_id message; do
  printf '{"version":2,"jjstack_version":"x","rules":[{"%s":"*","reason":"noisy"}],"fingerprints":[]}\n' \
    "$wk" > "$RB/wild.json"
  "$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/wild.json" \
    > "$RB/wild.out" 2>/dev/null; rc=$?
  check "wildcard rule on $wk exits 2, suppresses nothing" \
    "[ $rc -eq 2 ] && [ ! -s '$RB/wild.out' ]"
done
printf '{"version":2,"jjstack_version":"x","rules":[{"path":"**","message":"*","reason":"noisy"}],"fingerprints":[]}\n' > "$RB/wild2.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/wild2.json" >/dev/null 2>&1; rc=$?
check "several universal globs together still exit 2" "[ $rc -eq 2 ]"
# Positive control — the guard must reject WILDCARDS, not globbing itself. A
# real glob with a discriminating character has to keep working, or the tests
# above would pass just as well with the rules feature switched off.
printf '{"version":2,"jjstack_version":"x","rules":[{"path":"b*","reason":"policy: b.py is vendored"}],"fingerprints":[]}\n' > "$RB/narrow.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/narrow.json" \
  --active-only > "$RB/narrow.out" 2>/dev/null; rc=$?
check "positive control: a real glob still suppresses" \
  "[ $rc -eq 1 ] && [ \"\$(wc -l < '$RB/narrow.out')\" -eq 1 ]"
check "positive control: it suppressed only b.py" "grep -q 'shell injection' '$RB/narrow.out'"

# PR #16 review (P1): `generate` built the doc from scratch with `rules: []` and
# opened "w", so following SKILL.md's documented flow for EXTENDING a baseline
# destroyed every human-written rule and previously accepted fingerprint.
printf '{"version":2,"jjstack_version":"x","rules":[{"id":"docs","reason":"human policy exclusion"}],"fingerprints":[{"hash":"sha256:1111111111111111111111111111111111111111111111111111111111111111","reason":"accepted by a human last quarter"}]}\n' \
  > "$RB/prior.json"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "second pass" \
  -o "$RB/prior.json" >/dev/null 2>&1; rc=$?
check "generate onto an existing baseline exits 0" "[ $rc -eq 0 ]"
check "the human-written RULE survives"      "grep -q 'human policy exclusion' '$RB/prior.json'"
check "the prior fingerprint survives"       "grep -q 'accepted by a human last quarter' '$RB/prior.json'"
check "the new findings are appended"        "[ \"\$(grep -c 'sha256:' '$RB/prior.json')\" -eq 3 ]"
# Positive control — merging must be idempotent, not merely additive: a second
# identical run must add nothing, or "3 fingerprints" would grow every run.
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "third pass" \
  -o "$RB/prior.json" >/dev/null 2>&1
check "positive control: re-running adds no duplicates" \
  "[ \"\$(grep -c 'sha256:' '$RB/prior.json')\" -eq 3 ]"
check "positive control: the merged file is still valid to apply" \
  "\"$BIN/jjstack-review-baseline\" apply '$RB/findings.jsonl' --baseline '$RB/prior.json' >/dev/null 2>&1; [ \$? -ne 2 ]"
# --replace is the explicit way to start over; nothing else may truncate.
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "fresh" \
  -o "$RB/prior.json" --replace >/dev/null 2>&1
check "--replace drops the prior rules on purpose" \
  "! grep -q 'human policy exclusion' '$RB/prior.json'"
# A corrupt existing baseline must stop the run, not be silently overwritten.
printf 'this is not json\n' > "$RB/corrupt.json"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "x" \
  -o "$RB/corrupt.json" >/dev/null 2>&1; rc=$?
check "generate refuses to clobber a corrupt baseline" "[ $rc -eq 2 ]"
check "the corrupt baseline is left untouched" "grep -q 'this is not json' '$RB/corrupt.json'"
check "no .tmp file is left behind" "[ ! -f '$RB/corrupt.json.tmp' ]"
printf '{"version":1,"rules":[],"fingerprints":[]}\n' > "$RB/v1.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/v1.json" >/dev/null 2>&1; rc=$?
check "unsupported baseline version exits 2" "[ $rc -eq 2 ]"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/gone.json" >/dev/null 2>&1; rc=$?
check "missing baseline exits 2" "[ $rc -eq 2 ]"

# Fingerprints fail CLOSED across a jjstack version change: they cannot be
# trusted to still mean what they meant, so they go inert rather than hide.
sed 's/"jjstack_version": ".*"/"jjstack_version": "0.0.0-ancient"/' "$RB/bl.json" > "$RB/old.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/old.json" \
  --active-only > "$RB/old.out" 2>/dev/null; rc=$?
check "version drift makes fingerprints inert" "[ \"\$(wc -l < '$RB/old.out')\" -eq 2 ]"
check "version drift is a warning, not a hide" "[ $rc -eq 1 ]"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/old.json" \
  --active-only --allow-version-drift > "$RB/ovr.out" 2>/dev/null
check "--allow-version-drift re-enables them"  "[ ! -s '$RB/ovr.out' ]"
# Positive control for the drift test — prove the two baselines really do
# differ in version, or "inert" above proves nothing.
check "positive control: drifted baseline has a different version" \
  "! cmp -s '$RB/bl.json' '$RB/old.json'"
rm -rf "$RB"

echo "== 6. review skill structural guards =="
# Two five-line greps that would have caught two defects the parallel PR stack
# actually produced, both invisible to a per-PR review against main:
#
#  1. A PR written against the OLD Phase 5 re-introduces the heading a later PR
#     deleted — and git merges that hunk WITHOUT reporting a conflict, because
#     the heading arrives as innocent context lines. Result: two "## Phase 5"
#     headings and two contradictory verification models in one file.
#  2. Three PRs independently created bin/jjstack-review-blast-radius with three
#     incompatible CLIs (--out DIR vs stdout). Whichever merged last won the
#     filename, and the caller that passes --out died with exit 2.
#
# These pass at this point in the chain and are meant to go RED the moment
# either defect is reintroduced downstream. That is the guard doing its job:
# the defect cannot land silently, which is how it landed the first time.
SK="$DIR/skills/review/SKILL.md"
n_phase5=$(grep -c '^## Phase 5: ' "$SK" 2>/dev/null)
check "exactly one '## Phase 5: ' heading in the review skill" "[ \"\$n_phase5\" = 1 ]"

n_blast=$(ls -1 "$BIN" 2>/dev/null | grep -c '^jjstack-review-blast-radius')
check "exactly one blast-radius implementation in bin/" "[ \"\$n_blast\" = 1 ]"

# Positive controls — a grep that can never fire looks exactly like a clean tree.
probe_sk="$(mktemp)"
printf '## Phase 5: one\nbody\n## Phase 5: two\n' > "$probe_sk"
check "phase-5 guard actually catches a duplicate" \
  "[ \"\$(grep -c '^## Phase 5: ' '$probe_sk')\" = 2 ]"
rm -f "$probe_sk"
probe_bin="$(mktemp -d)"
: > "$probe_bin/jjstack-review-blast-radius"; : > "$probe_bin/jjstack-review-blast-radius-census"
check "blast-radius guard actually catches a duplicate" \
  "[ \"\$(ls -1 '$probe_bin' | grep -c '^jjstack-review-blast-radius')\" = 2 ]"
rm -rf "$probe_bin"

# Every disposition must route to a section 5f actually defines. Two separate
# PRs independently routed findings to "the appendix" — a section that stopped
# existing when verification became enrich-only. A finding with a disposition
# and nowhere to be printed is invisible in exactly the way this skill exists to
# prevent, and prose review missed it twice.
#
# The FIRST version of this guard was itself a false pass, in both halves, and
# that is the more expensive lesson:
#
#  1. Its regex was 'to the \*{0,2}appendix\*{0,2}', which requires "appendix"
#     to follow "to the" immediately. Not one of the six strings that actually
#     shipped is written that way — they say "to the report appendix", "to the
#     report's appendix", "or `appendix`". The regex was written to match the
#     probe, and the probe was invented to match the regex, so the pair proved
#     only that they agreed with each other.
#  2. It grepped SKILL.md alone, while the surviving routings lived in
#     references/ and CHANGELOG.md.
#
# So: the corpus is now every file that can carry a routing instruction, the
# test is the bare word (a rephrasing cannot dodge it — this guard is meant to
# fail closed, and if a section named "appendix" is ever wanted, 5f must define
# it first), and the positive control below is built from the literal strings
# this tree really contained, recovered from git, not from anything invented
# here.
ROUTE_CORPUS=("$SK" "$DIR/CHANGELOG.md" "$DIR"/references/*.md "$BIN"/jjstack-review-*)
# An unexpanded glob or a moved file is how a widened corpus silently narrows
# again: grep cannot read the path, says nothing, and reports a clean tree.
route_missing=0
for f in "${ROUTE_CORPUS[@]}"; do [ -f "$f" ] || route_missing=$((route_missing + 1)); done
check "positive control: every file in the routing corpus exists" "[ $route_missing -eq 0 ]"
check "positive control: the corpus reaches past SKILL.md into references/" \
  "[ \"\$(printf '%s\n' \"\${ROUTE_CORPUS[@]}\" | grep -c '/references/')\" -ge 3 ]"
check "positive control: the corpus includes the changelog" \
  "printf '%s\n' \"\${ROUTE_CORPUS[@]}\" | grep -q '/CHANGELOG\.md\$'"
check "positive control: the corpus includes the ledger tool" \
  "printf '%s\n' \"\${ROUTE_CORPUS[@]}\" | grep -q '/jjstack-review-ledger\$'"

# No -c: over several files `grep -c` prints one count PER FILE, so piping that
# to `wc -l` would count files and report a constant. Count matching lines.
n_appendix=$(grep -inE 'appendix' "${ROUTE_CORPUS[@]}" 2>/dev/null | wc -l | tr -d ' ')
check "no finding is routed to a section 5f does not define" "[ \"\$n_appendix\" = 0 ]"
check "the Demoted section it routes to instead exists" \
  "grep -q '^### Demoted (prior decision)' '$SK'"

# POSITIVE CONTROL — every line below is a LITERAL that this repository really
# shipped (recovered with `git grep -i appendix HEAD` at 754d63d), not a string
# written to satisfy the pattern. That distinction is the whole finding: the old
# control fired on a synthetic "to the **appendix**" that no file ever contained,
# which is how the guard stayed green while six real routings survived.
probe_sec="$(mktemp)"
{
  printf '# match here DEMOTES a finding to the report appendix with the prior decision\n'
  printf '        echo "the report appendix with this note cited — they never drop it. Delete a"\n'
  printf '**demotes**: a matched dismissal moves a finding to the report appendix with the\n'
  printf "  A finding you previously dismissed moves to the report's appendix with your own\n"
  printf '  demote a finding into the appendix or the suppressed section, never out of the\n'
  printf '  as: reason `not-reachable` is legal only with `defer` or `appendix`.\n'
} > "$probe_sec"
check "routing guard catches all 6 shipped phrasings" \
  "[ \"\$(grep -icE 'appendix' '$probe_sec')\" = 6 ]"
# And the meta-control: prove the OLD regex really was blind to them, so this
# rewrite is a fix and not a restatement.
check "the regex it replaced missed 5 of those 6 shipped strings" \
  "[ \"\$(grep -icE 'to the \\*{0,2}appendix\\*{0,2}' '$probe_sec')\" = 1 ]"
# The strongest control of the three: run the guard's exact MULTI-FILE
# expression over a corpus that does contain shipped routings. "The files exist"
# and "the pattern matches one file" together still do not prove the real
# invocation counts — that seam is where `grep -c` over many files silently
# counts files instead of lines and pins the total to a constant.
probe_corpus="$(mktemp -d)"
cp "$probe_sec" "$probe_corpus/a.md"; : > "$probe_corpus/b.md"; : > "$probe_corpus/c.md"
check "the guard's own multi-file count finds all 6, not one-per-file" \
  "[ \"\$(grep -inE 'appendix' '$probe_corpus'/*.md 2>/dev/null | wc -l | tr -d ' ')\" = 6 ]"
rm -rf "$probe_corpus"
rm -f "$probe_sec"
echo "== 7a. review-sweep (post-fix deterministic checks) =="
# /review's post-pass 4 re-runs the project's typechecker/linter/tests AFTER the
# fixes land, to catch a fix that broke the build. The two states that must never
# be confused are "ran and passed" (0) and "nothing to run" (4) — a skipped sweep
# reported as clean is exactly the lie the pass exists to prevent.
SW="$(mktemp -d)"
"$BIN/jjstack-review-sweep" --repo "$SW" >/dev/null 2>&1; rc=$?
check "no checks available exits 4 (skip, not pass)" "[ $rc -eq 4 ]"
out=$("$BIN/jjstack-review-sweep" --repo "$SW" 2>&1)
check "skip message says SKIPPED, not clean" "printf '%s' \"\$out\" | grep -qi 'skip'"
"$BIN/jjstack-review-sweep" --repo "$SW" --cmd "true" >/dev/null 2>&1; rc=$?
check "all checks green exits 0" "[ $rc -eq 0 ]"
# Positive control — a failure detector that can never fire looks exactly like a
# permanently green build, which is how a broken sweep ships for months.
"$BIN/jjstack-review-sweep" --repo "$SW" --cmd "false" >/dev/null 2>&1; rc=$?
check "FAIL path actually fires (exit 1 on a failing check)" "[ $rc -eq 1 ]"
out=$("$BIN/jjstack-review-sweep" --repo "$SW" --cmd "true" --cmd "false" 2>&1)
check "a failing check among passing ones still fails" "printf '%s' \"\$out\" | grep -q 'SWEEP BROKEN'"
# --dry-run prints the plan and runs nothing.
"$BIN/jjstack-review-sweep" --repo "$SW" --cmd "touch '$SW/ran'" --dry-run >/dev/null 2>&1
check "--dry-run executes no command" "[ ! -f '$SW/ran' ]"
"$BIN/jjstack-review-sweep" --repo "$SW" --timeout abc --cmd true >/dev/null 2>&1; rc=$?
check "non-numeric --timeout is a usage error (2)" "[ $rc -eq 2 ]"
rm -rf "$SW"

echo "== 7b. review-autofix-diff (the reviewer's own unreviewed diff) =="
# gstack's fix-first step auto-applies fixes; nothing reviews that code. This
# script isolates it as a diff. Fixture is a throwaway git repo; XDG_CACHE_HOME
# is redirected so the baseline marker never touches the real cache.
AFD="$(mktemp -d)"; export XDG_CACHE_HOME="$AFD/cache"
git -C "$AFD" init -q 2>/dev/null
git -C "$AFD" config user.email smoke@example.com
git -C "$AFD" config user.name "smoke"
printf 'one\n' > "$AFD/a.txt"; printf 'one\n' > "$AFD/b.txt"
git -C "$AFD" add -A >/dev/null 2>&1
git -C "$AFD" commit -qm base >/dev/null 2>&1
"$BIN/jjstack-review-autofix-diff" --repo "$AFD" >/dev/null 2>&1; rc=$?
check "clean tree = no auto-fixes, exits 4" "[ $rc -eq 4 ]"
# A pre-existing dirty edit, then a marker, then the "auto-fix". Only the latter
# is the reviewer's work, and only it may appear in the diff.
printf 'PRE_EXISTING\n' >> "$AFD/b.txt"
"$BIN/jjstack-review-autofix-diff" --repo "$AFD" --mark >/dev/null 2>&1
printf 'AUTOFIXED\n' >> "$AFD/a.txt"
out=$("$BIN/jjstack-review-autofix-diff" --repo "$AFD" 2>&1); rc=$?
# Positive control — the exit-4 guard would also be silent if detection were
# simply broken, so prove the detector finds a real change before trusting a 4.
check "detects the post-marker change (exit 0)" "[ $rc -eq 0 ]"
check "diff contains the auto-fix"              "printf '%s' \"\$out\" | grep -q 'AUTOFIXED'"
check "marker excludes pre-existing dirt"       "! printf '%s' \"\$out\" | grep -q 'PRE_EXISTING'"
# Without a marker the fallback is HEAD, and it must SAY that it over-claims.
rm -rf "$XDG_CACHE_HOME"
out=$("$BIN/jjstack-review-autofix-diff" --repo "$AFD" 2>&1)
check "HEAD fallback discloses its caveat" "printf '%s' \"\$out\" | grep -q 'fallback HEAD'"
check "HEAD fallback sees pre-existing dirt" "printf '%s' \"\$out\" | grep -q 'PRE_EXISTING'"
# New files an auto-fix creates are untracked and invisible to `git diff`.
printf 'x\n' > "$AFD/new_file.txt"
out=$("$BIN/jjstack-review-autofix-diff" --repo "$AFD" 2>&1)
check "untracked new files are surfaced" "printf '%s' \"\$out\" | grep -q 'new_file.txt'"
"$BIN/jjstack-review-autofix-diff" --repo "$AFD/nope" >/dev/null 2>&1; rc=$?
check "non-repo path exits 3" "[ $rc -eq 3 ]"
unset XDG_CACHE_HOME
rm -rf "$AFD"

echo "== 7c. review-calibration (accept/reject memory) =="
# Post-pass 5: a class the team keeps rejecting must be ranked DOWN THE PAGE and a
# class they keep confirming ranked up, or the reviewer re-guesses every run.
# Nothing leaves the report and no confidence ever moves — this is ordering only.
# The value is entirely in the key normalization (same class -> same row) and the
# clamped, placement-only rank arithmetic.
CAL="$(mktemp -d)"; LEDGER="$CAL/review-calibration.tsv"
"$BIN/jjstack-review-calibration" report --store "$LEDGER" >/dev/null 2>&1; rc=$?
check "no ledger yet exits 4 (skip, no adjustment)" "[ $rc -eq 4 ]"
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "Unused Import!!" --verdict rejected >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "unused-import" --verdict rejected >/dev/null 2>&1
out=$("$BIN/jjstack-review-calibration" suggest --store "$LEDGER" --key "UNUSED import" 2>&1)
check "keys normalize to one row across spellings" "printf '%s' \"\$out\" | grep -q 'rejected=2'"
check "two rejections rank the pattern at -20"     "grep -q 'rank=-20' <<<\"\$out\""
check "a negative rank demotes rather than rescores" "grep -q 'placement=demoted' <<<\"\$out\""
# The whole point of the rewrite: calibration must never emit an instruction to
# change a finding's confidence. The score is a claim about the code; the
# demotion is a claim about the team's prior decision.
check "suggest never emits a confidence delta"     "! grep -qi 'delta=' <<<\"\$out\""
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "unused-import" --verdict rejected >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "unused-import" --verdict rejected >/dev/null 2>&1
out=$("$BIN/jjstack-review-calibration" suggest --store "$LEDGER" --key "unused-import" 2>&1)
check "rank is floored at -30" "grep -q 'rank=-30' <<<\"\$out\""
for _ in 1 2 3; do
  "$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "missing-migration" --verdict accepted >/dev/null 2>&1
done
out=$("$BIN/jjstack-review-calibration" suggest --store "$LEDGER" --key "missing migration" 2>&1)
check "rank is capped at +20" "grep -q 'rank=20' <<<\"\$out\""
# A confirmed pattern ranks up but must NOT be demoted, and must still not carry
# a score instruction — promotion is placement too.
check "a positive rank keeps normal placement" "grep -q 'placement=normal' <<<\"\$out\""
out=$("$BIN/jjstack-review-calibration" suggest --store "$LEDGER" --key "never-seen" 2>&1); rc=$?
check "unknown key exits 4 with no adjustment" "[ $rc -eq 4 ]"
check "unknown key reports rank=0"             "grep -q 'rank=0' <<<\"\$out\""
# Positive control — verdict validation that never rejects anything would let a
# typo ("acccepted") silently become an uncounted row, and the ledger would rot
# while every read still looked healthy.
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key k --verdict acccepted >/dev/null 2>&1; rc=$?
check "invalid verdict actually rejected (exit 2)" "[ $rc -eq 2 ]"
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --verdict accepted >/dev/null 2>&1; rc=$?
check "missing --key is a usage error (2)" "[ $rc -eq 2 ]"
# Field-count integrity: a tab in free text would shift every column after it.
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "tabby" --verdict accepted --note "a	b	c" >/dev/null 2>&1
check "tabs in --note cannot corrupt the row" "awk -F'\t' '/tabby/{exit !(NF==6)}' '$LEDGER'"
before=$(wc -l < "$LEDGER")
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "dry" --verdict accepted --dry-run >/dev/null 2>&1
check "--dry-run appends nothing" "[ \$(wc -l < '$LEDGER') -eq $before ]"
rm -rf "$CAL"
echo "== 7d. review-triage (no-silent-drop invariants + dedup + exposure) =="
# /review casts wide on purpose, so the interesting question is not what it
# reports but what it decided NOT to report. This script is the accountability
# layer: every finding gets a disposition and a reason code, three invariants
# are machine-enforced, and dedup/exposure/corroboration are computed rather
# than guessed. Guards that can't fire are worthless, so each invariant below
# has a POSITIVE CONTROL feeding it input that must be rejected.
TRI="$(mktemp -d)"
# One ledger row: 7 fields joined by real tabs. Hand-writing the tabs into a
# format string is how the first draft of these tests silently produced
# 6-column rows, so the join lives in one place.
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

# A well-formed ledger: two lenses on the same defect (must collapse), one
# demoted-by-prior-decision item, one baseline-suppressed nit, one deferred
# vendor finding. Dispositions track the enrich-only model — no score bands.
{
  row P1 80 src/auth.py:42      security    report   -              'missing authz check on admin route'
  row P1 72 src/auth.py:42      correctness report   -              'Missing authz check on admin route!'
  row P2 55 src/util.py:9       perf        demoted  prior-decision 'N+1 query in loop'
  row P3 30 tests/test_x.py:5   style       suppress baseline       'trailing whitespace'
  row P2 40 vendor/lib/x.js:100 security    defer    not-reachable  'unused eval path'
} > "$TRI/good.tsv"

"$BIN/jjstack-review-triage" "$TRI/good.tsv" --out "$TRI/good.md" > "$TRI/good.out" 2> "$TRI/good.err"
rc=$?
check "review-triage exits 0 on a valid ledger" "[ $rc -eq 0 ]"
check "renders a ledger to --out"               "[ -f '$TRI/good.md' ]"
check "dedups two lenses on one defect"         "grep -q 'unique=4 collapsed=1' '$TRI/good.out'"
check "counts corroborating lenses"             "grep -q 'security, correctness' '$TRI/good.md'"
check "classifies a src path as prod exposure"  "grep -q 'src/auth.py:42\` | prod' '$TRI/good.md'"
check "classifies a tests/ path as test"        "grep -q 'tests/test_x.py:5\` | test' '$TRI/good.md'"
check "classifies node_modules-style vendor"    "grep -q 'vendor/lib/x.js:100\` | vendor' '$TRI/good.md'"
# The core claim: a suppressed finding is still on the page, with its reason.
check "suppressed finding stays visible"        "grep -q 'trailing whitespace' '$TRI/good.md'"
check "suppressed finding records its reason"   "grep -q 'baseline' '$TRI/good.md'"
# A demoted finding is ACTIVE — it must be printed, keeping its own severity and
# confidence. Demotion is a claim about the team's prior decision, never a
# rescoring of the finding.
check "demoted finding stays on the page"       "grep -q 'N+1 query in loop' '$TRI/good.md'"
check "demoted finding keeps its confidence"    "grep -qE '\\| P2 \\| 55 \\|' '$TRI/good.md'"
check "demoted has its own section"             "grep -q 'Demoted (prior decision)' '$TRI/good.md'"

# POSITIVE CONTROL 1 — a disposition other than `report` with no reason code
# is the silent drop this whole script exists to make impossible.
row P2 30 src/a.py:1 sec suppress - 'dropped with no reason' > "$TRI/silent.tsv"
"$BIN/jjstack-review-triage" "$TRI/silent.tsv" --out "$TRI/silent.md" > /dev/null 2> "$TRI/silent.err"
rc=$?
check "POSITIVE CONTROL: silent drop rejected (exit 4)" "[ $rc -eq 4 ]"
check "silent drop names the invariant"                 "grep -q 'never dropped silently' '$TRI/silent.err'"
check "invalid ledger renders nothing"                  "[ ! -f '$TRI/silent.md' ]"

# POSITIVE CONTROL 2 — reachability may deprioritise, never delete.
row P2 30 src/b.py:1 sec suppress not-reachable 'deleted via reachability' > "$TRI/reach.tsv"
"$BIN/jjstack-review-triage" "$TRI/reach.tsv" > /dev/null 2> "$TRI/reach.err"
rc=$?
check "POSITIVE CONTROL: not-reachable cannot suppress (exit 4)" "[ $rc -eq 4 ]"
check "not-reachable error offers defer/demoted instead"         "grep -q 'deprioritise' '$TRI/reach.err'"

# POSITIVE CONTROL 3 — a P0/P1 may be deferred, never made to disappear.
row P0 90 src/c.py:1 sec suppress style-only 'top severity vanished' > "$TRI/p0.tsv"
"$BIN/jjstack-review-triage" "$TRI/p0.tsv" > /dev/null 2> "$TRI/p0.err"
rc=$?
check "POSITIVE CONTROL: P0 cannot be suppressed (exit 4)" "[ $rc -eq 4 ]"
check "P0 error names the severity"                        "grep -q 'P0 may not be suppressed' '$TRI/p0.err'"

# Vocabulary is closed — an invented reason code is a failure, not a passthrough.
row P2 30 src/d.py:1 sec defer feels-fine 'invented reason code' > "$TRI/vocab.tsv"
"$BIN/jjstack-review-triage" "$TRI/vocab.tsv" > /dev/null 2> "$TRI/vocab.err"
rc=$?
check "POSITIVE CONTROL: unknown reason code rejected" "[ $rc -eq 4 ]"

# Reporting a finding in code nobody here authored is advisory noise, not fatal.
row P2 70 node_modules/x/y.js:3 sec report - 'vendor finding reported' > "$TRI/adv.tsv"
"$BIN/jjstack-review-triage" "$TRI/adv.tsv" > /dev/null 2> "$TRI/adv.err"
rc=$?
check "vendor-path report warns but still exits 0" "[ $rc -eq 0 ]"
check "vendor-path report emits an ADVISORY"       "grep -q 'ADVISORY' '$TRI/adv.err'"

# A missing ledger is a clean exit 3, not a crash or a silent success.
"$BIN/jjstack-review-triage" "$TRI/nope.tsv" > /dev/null 2>&1
rc=$?
check "missing ledger exits 3" "[ $rc -eq 3 ]"

# --- REGRESSION: dedup absorbed a reported P0 into a suppressed P3 ----------
# The three invariants used to run PER ROW, BEFORE dedup, and dedup kept only
# the first-seen row. Two findings at one location whose claims share an
# opening phrase share a fingerprint, so a baseline-suppressed P3 sorted first
# SWALLOWED a reported P0: TALLY report=0 suppress=1, exit 0, rendered as a
# suppressed P3 — under a header promising every finding was on the page.
# Invariant 3 never fired, because the P0 row itself said `report`. The
# suppression happened by ABSORPTION, not by violation.
{
  row P3 20 src/a.py:10 style    suppress baseline 'the request handler does not validate the incoming field length'
  row P0 95 src/a.py:10 security report   -        'the request handler does not validate the incoming token allowing auth bypass'
} > "$TRI/absorb.tsv"
"$BIN/jjstack-review-triage" "$TRI/absorb.tsv" --out "$TRI/absorb.md" > "$TRI/absorb.out" 2>&1
rc=$?
check "merged group is not suppressed (exit 0)"    "[ $rc -eq 0 ]"
check "merge keeps the HIGHEST severity"           "grep -q '| P0 | 95 |' '$TRI/absorb.md'"
check "merge keeps the WEAKEST disposition"        "grep -q 'report=1 unconfirmed=0 demoted=0 defer=0 suppress=0' '$TRI/absorb.out'"
check "absorbed P0 lands in the reported section"  "grep -q 'allowing auth bypass' '$TRI/absorb.md'"
check "suppressed section no longer holds the P0"  "! grep -q 'field length' '$TRI/absorb.md'"
check "the merge itself is audited on the page"    "grep -q 'P3 → P0' '$TRI/absorb.md'"
check "the merge records the disposition change"   "grep -q 'suppress → report' '$TRI/absorb.md'"
# POSITIVE CONTROL 4 — proof that the post-dedup pass genuinely runs on the
# MERGED record and not on the first-seen row. The vendor/generated advisory
# lives in that same pass, and it is the one signal a per-row implementation
# provably gets wrong: a vendor finding first seen as `suppress` that only
# becomes `report` through the merge emitted NO advisory before this fix, and
# emits one now. Same collision recipe as the absorption case, on a vendor path.
{
  row P3 20 vendor/lib/x.js:5 style    suppress baseline 'the bundled helper concatenates the incoming request value without any check'
  row P1 88 vendor/lib/x.js:5 security report   -        'the bundled helper concatenates the incoming request value into a shell command'
} > "$TRI/vendmerge.tsv"
"$BIN/jjstack-review-triage" "$TRI/vendmerge.tsv" --out "$TRI/vendmerge.md" > /dev/null 2> "$TRI/vendmerge.err"
check "POSITIVE CONTROL: merged-up vendor report warns after the merge" \
      "grep -q 'vendor/lib/x.js:5 (vendor) is reported' '$TRI/vendmerge.err'"
# Defence in depth: an all-suppressed group whose merged severity is P0 must
# never render. The per-row check already rejects this input, and the merged
# check rejects it again — invariant 3 must hold on both sides of the collapse.
{
  row P3 20 src/e.py:7 style    suppress baseline 'the parser accepts a header value without any bound'
  row P0 91 src/e.py:7 security suppress baseline 'the parser accepts a header value without checking the signature'
} > "$TRI/absorb2.tsv"
"$BIN/jjstack-review-triage" "$TRI/absorb2.tsv" --out "$TRI/absorb2.md" > /dev/null 2> "$TRI/absorb2.err"
rc=$?
check "an all-suppressed merge reaching P0 is rejected" "[ $rc -eq 4 ]"
check "merged P0 rejection renders nothing"             "[ ! -f '$TRI/absorb2.md' ]"
# A group that agrees changes nothing, so it must NOT be listed as a merge —
# otherwise the Merges section is noise and nobody reads the real entries.
check "an agreeing dedup is not reported as a merge" "grep -q 'merges-raised=0' '$TRI/good.out'"

# --- REGRESSION: an unescaped `|` in a claim shifted the markdown table -----
# `lenslist()` already stripped `|` from the lens column, so the hazard was
# known for one field and missed for the other. A claim quoting `a || b`
# produced a 9-cell row against a 7-cell header and renderers dropped the
# overflow, making the finding text unreadable in the committed artifact.
row P2 50 src/x.py:3 correctness report - 'the guard uses a || b when it should use a && b' > "$TRI/pipe.tsv"
"$BIN/jjstack-review-triage" "$TRI/pipe.tsv" --out "$TRI/pipe.md" > /dev/null 2>&1
check "pipe in a claim is escaped for the table" "grep -q 'a \\\\|\\\\| b' '$TRI/pipe.md'"
# POSITIVE CONTROL 5 — count the cells a renderer would actually see: strip
# the escapes, then the row must have exactly 7 cells like its header.
cells=$(grep 'src/x.py:3' "$TRI/pipe.md" | sed 's/\\|//g' | awk -F'|' '{print NF-2}')
check "POSITIVE CONTROL: escaped row still renders 7 cells" "[ '$cells' = 7 ]"
check "the claim text survives intact"                      "grep -q 'when it should use a && b' '$TRI/pipe.md'"

# --- REGRESSION: "write the complete merged set" was enforced nowhere -------
# A TSV of nothing but comments rendered six `_none_` sections and exited 0 —
# a ledger certifying "every finding is on this page" while listing none.
# Phase 5d already emits findings.adjudicated.jsonl, so completeness is a
# deterministic count, not a promise.
printf '# nothing but a comment\n\n' > "$TRI/empty.tsv"
adj() { printf '{"lens":"%s","file":"%s","start_line":%s,"severity":"%s","confidence":0.9,"message":"%s","quote":"q","explanation":"e","remediation":"r"}\n' "$1" "$2" "$3" "$4" "$5"; }
{
  adj security src/a.py 10 P0 'auth bypass'
  adj perf     src/b.py 4  P2 'n+1 query'
} > "$TRI/adjudicated.jsonl"
"$BIN/jjstack-review-triage" "$TRI/empty.tsv" --out "$TRI/empty.md" > /dev/null 2> "$TRI/empty.err"
rc=$?
check "an empty ledger still exits 0 unreconciled" "[ $rc -eq 0 ]"
check "empty unreconciled ledger warns it certifies nothing" "grep -q 'certifies nothing' '$TRI/empty.err'"
check "unreconciled header does not claim completeness"      "grep -q 'was NOT verified' '$TRI/empty.md'"
# POSITIVE CONTROL 6 — the same empty ledger against a real adjudicated set
# must refuse to render and name every finding that left without a disposition.
"$BIN/jjstack-review-triage" "$TRI/empty.tsv" --reconcile "$TRI/adjudicated.jsonl" \
  --out "$TRI/recon.md" > /dev/null 2> "$TRI/recon.err"
rc=$?
check "POSITIVE CONTROL: a dropped finding fails reconciliation (exit 4)" "[ $rc -eq 4 ]"
check "reconciliation names the missing location"  "grep -q 'src/a.py:10' '$TRI/recon.err'"
check "failed reconciliation renders nothing"      "[ ! -f '$TRI/recon.md' ]"
# The complete ledger reconciles, and only then does the page claim completeness.
{
  row P0 90 src/a.py:10 security report -            'auth bypass'
  row P2 50 src/b.py:4  perf     defer  pre-existing 'n+1 query'
} > "$TRI/full.tsv"
"$BIN/jjstack-review-triage" "$TRI/full.tsv" --reconcile "$TRI/adjudicated.jsonl" \
  --out "$TRI/full.md" > /dev/null 2>&1
rc=$?
check "a complete ledger reconciles (exit 0)"          "[ $rc -eq 0 ]"
check "reconciled header states it is a checked fact"  "grep -q 'checked fact, not a promise' '$TRI/full.md'"
check "reconciled ledger names its adjudicated source" "grep -q 'reconciled against' '$TRI/full.md'"
# A missing adjudicated file is exit 3, the same clean signal as a missing ledger.
"$BIN/jjstack-review-triage" "$TRI/full.tsv" --reconcile "$TRI/nope.jsonl" > /dev/null 2>&1
rc=$?
check "missing --reconcile file exits 3" "[ $rc -eq 3 ]"

# --- REGRESSION: --help truncated at a hardcoded line number ----------------
# `sed -n '2,43p'` cut the block before the Exit line, so the documented exit
# codes — including the exit 4 the whole design hinges on — never reached the
# user. The range is now computed from the comment block itself.
"$BIN/jjstack-review-triage" --help > "$TRI/help.txt" 2>&1
check "--help documents the exit codes"      "grep -q 'Exit: 0 ledger valid' '$TRI/help.txt'"
check "--help documents exit 4"              "grep -q '4 validation failed' '$TRI/help.txt'"
check "--help documents --reconcile"         "grep -q -- '--reconcile' '$TRI/help.txt'"
# POSITIVE CONTROL 7 — the help must stop at the code, not spill the script.
check "POSITIVE CONTROL: --help stops at the comment block" "! grep -q 'set -uo pipefail' '$TRI/help.txt'"
rm -rf "$TRI"
echo "== 7e. review-blast-radius (generic threshold + cross-repo) =="
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

echo "== 7f. review-ledger (dismissal memory that demotes, never drops) =="
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

# Rule 4: a record only speaks about a finding whose PATH it matches. The
# protected branch used to print and `continue` before the glob was ever tested,
# so a dismissal recorded against 'docs/*' announced itself on a security
# finding in 'src/payments.py'. The skill then tells the reviewer to cite that
# prior dismissal in the finding body: a fabricated precedent, pointing at a
# live P0. The pre-existing protected test could not catch it because its glob
# ('src/*' vs 'src/a.py') happened to match.
LDG="$(mktemp -d)/ledger.md"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'docs/*' --category security \
  --note 'docs only' --ledger "$LDG" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'src/payments.py' --category security \
  --ledger "$LDG" > "$LDG.out" 2>/dev/null
check "a protected record whose glob does NOT match stays silent" "[ ! -s '$LDG.out' ]"
# POSITIVE CONTROL — the same record on a path its glob DOES match must still
# announce, or "stays silent" would merely mean PROTECTED reporting is broken.
"$BIN/jjstack-review-ledger" --match --path 'docs/readme.md' --category security \
  --ledger "$LDG" > "$LDG.hit" 2>/dev/null
check "positive control: the same record DOES announce on a matching path" \
  "grep -q 'PROTECTED' '$LDG.hit'"

# Rule 5: a dismissal is a decision about a place in the code, not a blanket.
# '*' has no literal character in it, so it matches every path in the repo and
# would demote every finding in its category, repo-wide and permanently — while
# reading like any other line in a PR diff. CATEGORY and TYPE both get
# closed-vocabulary checks; the other half of the key was unchecked.
"$BIN/jjstack-review-ledger" --record --type dismissed --path '*' --category style \
  --ledger "$LDG" >/dev/null 2>&1
check "an unscoped '*' path glob exits 2" "[ \$? -eq 2 ]"
"$BIN/jjstack-review-ledger" --record --type dismissed --path '*/*' --category style \
  --ledger "$LDG" >/dev/null 2>&1
check "'*/*' is unscoped too"             "[ \$? -eq 2 ]"
# POSITIVE CONTROL — a glob that names a real place must still be accepted, or
# the guard could simply be rejecting every --record.
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/legacy/*' --category style \
  --ledger "$LDG" >/dev/null 2>&1
check "positive control: a scoped glob is still recorded" "[ \$? -eq 0 ]"

# Rule 6: the note is quoted by the skill as the demotion reason, so it must
# survive the round trip whole. The reader took field 6 of a '|'-separated line,
# which truncated any note containing a pipe at the first one — silently
# dropping the condition attached to the dismissal.
LDP="$(mktemp -d)/ledger.md"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
  --note 'safe today | revisit when we drop py38' --ledger "$LDP" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style \
  --ledger "$LDP" > "$LDP.out" 2>/dev/null
check "a note containing '|' survives the round trip" \
  "grep -q 'revisit when we drop py38' '$LDP.out'"
# POSITIVE CONTROL — prove the note was really written with the pipe in it, and
# that the line really did demote, or the grep proves nothing about parsing.
check "positive control: the recorded line really contains the pipe" \
  "grep -q 'safe today | revisit' '$LDP'"
check "positive control: that record really demoted" "grep -q '^DEMOTE ' '$LDP.out'"

# Rule 7: "no ledger" and "no prior decision applies" are different statements.
# --match exited 1 in silence for a missing file, so a mistyped --ledger path
# was reported to the reviewer as an authoritative all-clear for the whole run.
out=$("$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style \
  --ledger "$LDP.nope" 2>&1); rc=$?
check "--match on a missing ledger still exits 1"  "[ $rc -eq 1 ]"
check "--match on a missing ledger is NOT silent"  "printf '%s' \"\$out\" | grep -qi 'no ledger'"
# POSITIVE CONTROL — a real ledger with no matching row must stay quiet, else
# "not silent" would just mean the tool warns unconditionally.
out=$("$BIN/jjstack-review-ledger" --match --path 'nowhere/x.py' --category style \
  --ledger "$LDP" 2>&1)
check "positive control: a real ledger with no match warns nothing" \
  "! printf '%s' \"\$out\" | grep -qi 'no ledger'"

# Rule 8: a flag given with no value must be a usage error, not a hang. `shift 2`
# is a NO-OP when one argument remains and `set -e` is off, so the arg loop
# re-read the same $1 for ever: `jjstack-review-ledger --list --ledger` spun
# until killed (verified rc=124 under `timeout 5`). An unattended /review step
# that spins is worse than one that crashes — nothing reports and nothing times
# out. Every value-taking flag is covered, since one unguarded arm is enough.
for vflag in --type --path --category --note --ledger --repo; do
  timeout 5 "$BIN/jjstack-review-ledger" --list "$vflag" >/dev/null 2>&1
  check "ledger $vflag with no value exits 2, never hangs" "[ \$? -eq 2 ]"
done
# POSITIVE CONTROL — `timeout` must really be able to report a hang here, or
# every check above would pass just as well against a script that cannot run.
timeout 2 bash -c 'while :; do :; done' >/dev/null 2>&1
check "positive control: timeout reports a real hang as 124" "[ \$? -eq 124 ]"
rm -rf "$(dirname "$LDG")" "$(dirname "$LDP")"
rm -rf "$(dirname "$LD")"

echo "== 7g. review-revert-history (files that burned us before) =="
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

# A SHALLOW clone has no history to search, and `git log --since` says so by
# returning nothing — which is indistinguishable from "searched two years, found
# nothing clean". `actions/checkout` fetches depth 1 by default, and /review's
# git-history pass is told to trust this file as a pre-computed input, so the
# report must never present a truncated search as a completed one. The old
# caveat named only the subject-line limitation: it told the reader the search
# was complete in the one dimension that had actually failed.
SH="$(mktemp -d)"
git clone -q --depth 1 "file://$RH" "$SH/clone" >/dev/null 2>&1
out=$("$BIN/jjstack-review-revert-history" --repo "$SH/clone" --diff-file "$RH/d.diff" 2>/dev/null)
check "a shallow clone is really shallow" \
  "[ \"\$(git -C '$SH/clone' rev-parse --is-shallow-repository 2>/dev/null)\" = true ]"
check "shallow report says the window is TRUNCATED" \
  "printf '%s' \"\$out\" | grep -q 'TRUNCATED'"
check "shallow report does not claim a clean history" \
  "! printf '%s' \"\$out\" | grep -q 'No revert, rollback or hotfix history on any changed file'"
check "shallow report says the history was NOT searched" \
  "printf '%s' \"\$out\" | grep -q 'the history was not'"
# POSITIVE CONTROL — the SAME diff against the FULL repo must find the incident
# and print no truncation notice. Without it, "says TRUNCATED" could just mean
# the script warns on every run, and "no clean claim" could mean it found the
# history after all.
out=$("$BIN/jjstack-review-revert-history" --repo "$RH" --diff-file "$RH/d.diff" 2>/dev/null)
check "positive control: the full clone finds the incident"   "printf '%s' \"\$out\" | grep -q 'pay.py'"
check "positive control: the full clone claims no truncation" "! printf '%s' \"\$out\" | grep -q 'TRUNCATED'"

# Same value-less-flag hang as the ledger: `shift 2` cannot shift 2 when one
# argument remains, and with `set -e` off the loop never advances.
for vflag in --repo --base --diff-file --since --limit; do
  timeout 5 "$BIN/jjstack-review-revert-history" "$vflag" >/dev/null 2>&1
  check "revert-history $vflag with no value exits 2, never hangs" "[ \$? -eq 2 ]"
done
rm -rf "$RH" "$NOGIT" "$SH"

echo "== 7e. value-less flags must be a usage error, never a hang =="
# Reproduced before the fix: every one of these returned 124 under `timeout 5`.
# `shift 2` is a silent no-op when only one argument remains, and `set -e` is
# deliberately off in these scripts, so the arg loop spun on the same argv
# forever. A hung review tool is worse than a broken one: it burns the session
# with no output at all. Each case runs under `timeout` and asserts NOT 124.
for spec in \
  "jjstack-review-sweep|--repo" \
  "jjstack-review-sweep|--cmd" \
  "jjstack-review-sweep|--timeout" \
  "jjstack-review-autofix-diff|--repo" \
  "jjstack-review-autofix-diff|--baseline" \
  "jjstack-review-calibration|report --store" \
  "jjstack-review-calibration|suggest --key" \
  "jjstack-review-calibration|record --verdict" ; do
  tool="${spec%%|*}"; args="${spec#*|}"
  timeout 5 "$BIN/$tool" $args >/dev/null 2>&1; rc=$?
  check "$tool ${args##* } with no value does not hang" "[ $rc -ne 124 ]"
  check "$tool ${args##* } with no value is a usage error (2)" "[ $rc -eq 2 ]"
done
# Positive control — `timeout` must actually be able to report 124 here, or every
# "does not hang" assertion above is vacuously true and a real hang ships green.
timeout 1 sleep 5 >/dev/null 2>&1; rc=$?
check "timeout harness actually reports 124 on a real hang" "[ $rc -eq 124 ]"
# Positive control — the flags must still ACCEPT a value; a guard that rejected
# everything would also never hang.
SWV="$(mktemp -d)"
timeout 30 "$BIN/jjstack-review-sweep" --repo "$SWV" --cmd "true" >/dev/null 2>&1; rc=$?
check "a flag WITH a value still works (exit 0)" "[ $rc -eq 0 ]"
rm -rf "$SWV"

echo "== 7f. --help is derived from the header, not a hand-kept line range =="
# A `sed -n 'A,Bp'` range drifts the moment a line is added: calibration's help
# stopped mid-sentence and dropped the Usage and Exit sections that usage() sends
# the reader to find, while its two siblings leaked `set -uo pipefail` and the
# raw colour definitions into their own help output.
for tool in jjstack-review-sweep jjstack-review-autofix-diff jjstack-review-calibration; do
  hout=$("$BIN/$tool" --help 2>&1)
  check "$tool --help leaks no shell source" \
    "! printf '%s' \"\$hout\" | grep -qE 'set -uo pipefail|\\\\033\\['"
  check "$tool --help reaches the Usage section"  "printf '%s' \"\$hout\" | grep -q '^Usage:'"
  check "$tool --help reaches the Exit section"   "printf '%s' \"\$hout\" | grep -q '^Exit'"
  check "$tool --help ends on the last header line" \
    "printf '%s' \"\$hout\" | grep -q 'No color red anywhere'"
done
# Positive control — the leak detector must be able to fire, or "no shell source"
# is a grep that never matches anything and the truncation ships green.
probe_help=$(printf 'Usage:\nset -uo pipefail\n')
check "help leak guard actually catches leaked source" \
  "printf '%s' \"\$probe_help\" | grep -qE 'set -uo pipefail'"

echo "== 7g. review-sweep PARTIAL: a check set with no test runner is not clean =="
# Detection only adds a tool that is installed, so a Python project with ruff but
# no pytest ran the linter alone and printed SWEEP CLEAN at exit 0 — while the
# pass's headline promise (catching the fix that turned a passing test red) went
# untested. The shim PATH makes the plan deterministic regardless of what this
# machine happens to have installed.
SHIM="$(mktemp -d)"; PSW="$(mktemp -d)"
printf '[project]\nname = "fixture"\n' > "$PSW/pyproject.toml"
ln -s "$(command -v bash)" "$SHIM/bash"
ln -s "$(command -v mktemp)" "$SHIM/mktemp"
ln -s "$(command -v rm)" "$SHIM/rm"
printf '#!/bin/sh\nexit 0\n' > "$SHIM/ruff"; chmod +x "$SHIM/ruff"
out=$(timeout 30 env PATH="$SHIM" "$BIN/jjstack-review-sweep" --repo "$PSW" 2>&1); rc=$?
check "lint-only plan exits 5 (partial), not 0"    "[ $rc -eq 5 ]"
check "partial says PARTIAL, never CLEAN"          "printf '%s' \"\$out\" | grep -q 'SWEEP PARTIAL'"
check "partial never prints SWEEP CLEAN"           "! printf '%s' \"\$out\" | grep -q 'SWEEP CLEAN'"
check "partial names the missing test runner"      "printf '%s' \"\$out\" | grep -q 'NO test runner'"
# Positive control — add a test runner to the SAME fixture and the SAME shim. If
# this did not flip to CLEAN/0 the partial check above would pass for the wrong
# reason: a sweep that can only ever say PARTIAL is just as broken.
printf '#!/bin/sh\nexit 0\n' > "$SHIM/pytest"; chmod +x "$SHIM/pytest"
out=$(timeout 30 env PATH="$SHIM" "$BIN/jjstack-review-sweep" --repo "$PSW" 2>&1); rc=$?
check "same plan plus a test runner exits 0"       "[ $rc -eq 0 ]"
check "with a test runner it says SWEEP CLEAN"     "printf '%s' \"\$out\" | grep -q 'SWEEP CLEAN'"
rm -rf "$SHIM" "$PSW"

echo "== 7h. the docs must not teach the deleted rescoring/deletion model =="
# The single guard that existed (a grep for 'delta=' on one command's stdout)
# could not see PROSE, which is exactly how four written copies of the deleted
# model survived a fix that corrected the tool. This guard reads the documents.
# CHANGELOG and README are in scope: the user-facing copy restated the deleted
# model too, and a guard that only reads the skill would let it survive there.
REVDOCS="$DIR/skills/review/SKILL.md $DIR/references/review-post-passes.md $DIR/CHANGELOG.md $DIR/README.md"
REVSRC="$BIN/jjstack-review-sweep $BIN/jjstack-review-autofix-diff $BIN/jjstack-review-calibration"
# Each literal below is an affirmative statement of a model this repo deleted:
# findings decaying/being promoted across a threshold, DISPROVEN dropping a
# finding, and calibration adjusting a confidence.
for phrase in \
  "decay out" "decays out" "across the gate" "reporting gate" \
  "drops the finding" "the finding drops" "no confidence adjustment"; do
  check "no doc teaches \"$phrase\"" \
    "! grep -qF -- '$phrase' $REVDOCS $REVSRC"
done
# The two rules those documents MUST still state, positively.
check "SKILL.md still forbids deleting a finding" \
  "grep -qF 'Never delete a finding' '$DIR/skills/review/SKILL.md'"
check "SKILL.md gives DISPROVEN a section instead of a delete" \
  "grep -qF 'Disproven by test' '$DIR/skills/review/SKILL.md'"
check "the post-pass reference gives DISPROVEN a section too" \
  "grep -qF 'Disproven by test' '$DIR/references/review-post-passes.md'"
check "the changelog does not promise findings get dropped or rescored" \
  "! grep -qE 'gets dropped|adjusts its.{0,30}confidence' '$DIR/CHANGELOG.md'"
check "the changelog documents the PARTIAL sweep state" \
  "grep -qF 'PARTIAL' '$DIR/CHANGELOG.md'"
# Positive control — the prose guard must be able to fire, or it is a grep over
# documents that can never match and the next copy of the model ships green.
probe_doc="$(mktemp)"
printf 'repeat false positives decay out of the report\n' > "$probe_doc"
check "prose guard actually catches the deleted model" \
  "grep -qF -- 'decay out' '$probe_doc'"
rm -f "$probe_doc"

echo "== 7i. --mark is actually invoked, not just implemented =="
# The marker is the ONLY thing separating the reviewer's auto-fixes from the
# user's own uncommitted work. Before this fix `--mark` appeared nowhere but the
# script and this test file, so post-pass 2 always fell back to HEAD and diffed
# the whole dirty tree — reporting the user's work back to them as P1s. The
# smoke suite was green the entire time because it exercised a branch the shipped
# workflow never reached.
check "SKILL.md invokes jjstack-review-autofix-diff --mark" \
  "grep -qF 'jjstack-review-autofix-diff --mark' '$DIR/skills/review/SKILL.md'"
check "the post-pass reference invokes --mark too" \
  "grep -qF 'jjstack-review-autofix-diff --mark' '$DIR/references/review-post-passes.md'"
# It has to be marked BEFORE gstack can auto-apply anything, i.e. before the
# Phase 2 delegation line — a marker taken afterwards baselines the fixes away.
check "the marker is taken before the gstack delegation" \
  "[ \$(grep -n 'jjstack-review-autofix-diff --mark' '$DIR/skills/review/SKILL.md' | head -1 | cut -d: -f1) -lt \$(grep -n 'cat ~/.claude/skills/gstack/review/SKILL.md' '$DIR/skills/review/SKILL.md' | head -1 | cut -d: -f1) ]"
# Positive control — prove the ordering comparison can fail, or "before" is an
# assertion that would hold for any two line numbers.
probe_ord="$(mktemp)"
printf 'cat ~/.claude/skills/gstack/review/SKILL.md\njjstack-review-autofix-diff --mark\n' > "$probe_ord"
check "ordering guard actually catches a late marker" \
  "[ \$(grep -n 'jjstack-review-autofix-diff --mark' '$probe_ord' | head -1 | cut -d: -f1) -gt \$(grep -n 'cat ~/.claude/skills/gstack/review/SKILL.md' '$probe_ord' | head -1 | cut -d: -f1) ]"
rm -f "$probe_ord"
echo "== 7j. review skill/reference internal consistency =="
# The triage invariants are stated in three places. When they disagree, the
# reference wins by accident: Phase 5.11 cat-s it BEFORE stating any rule, so a
# wrong disposition name there is the first thing the model reads. `appendix`
# was never a disposition and 5f never defined such a section.
AIK="$DIR/references/vendor-lessons-aikido.md"
SKR="$DIR/skills/review/SKILL.md"
check "no phantom \`appendix\` disposition in the reference" "! grep -q 'appendix' '$AIK'"
check "no phantom \`appendix\` disposition in the skill"     "! grep -q 'appendix' '$SKR'"
check "reference states invariant 2 with a real disposition" \
      "grep -q 'not-reachable\` is legal only with \`defer\` or \`demoted\`' '$AIK'"
check "reference cross-references the triage phase (5.11)"   "grep -q 'Phase 5.11 now files' '$AIK'"
# The skill told the model to write the baseline's free-text reason into a
# column the validator gates on a closed vocabulary — exit 4 on a ledger that
# said exactly what the skill asked for, and Phase 5.11 offers no way out.
check "skill maps the baseline row to the \`baseline\` code" \
      "grep -q 'committed baseline (§5d) | \`suppress\` | \`baseline\` |' '$SKR'"
check "skill spells out that reason is a closed vocabulary" \
      "grep -q 'never free text' '$SKR'"
# Every disposition and reason the skill's mapping table names must exist in
# the script's vocabulary — the class of defect, not just the two instances.
for tok in report unconfirmed demoted defer suppress out-of-scope; do
  check "skill disposition \`$tok\` exists in the script" \
        "grep -q 'split(\"report unconfirmed demoted defer suppress out-of-scope\"' '$BIN/jjstack-review-triage'"
done
for tok in unverified prior-decision baseline pre-existing not-reachable accepted-risk tool-covered style-only no-repro duplicate; do
  check "skill reason \`$tok\` exists in the script vocabulary" \
        "grep -q '\\b$tok\\b' '$BIN/jjstack-review-triage'"
done

echo
if [ "$fail" -eq 0 ]; then printf '\033[92mALL %d PASS\033[0m\n' "$pass"; exit 0
else printf '\033[95m%d FAIL\033[0m, %d pass\n' "$fail" "$pass"; exit 1; fi
