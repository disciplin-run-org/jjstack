#!/bin/bash
# smoke.sh — regression smoke tests for the jjstack memory system.
#
# Deterministic, fast, and HERMETIC: syntax checks, pure library functions, and
# --dry-run paths, all run against a throwaway $HOME and throwaway fixture
# projects. The tests that write do so inside that sandbox and it is removed on
# exit. Codifies the behaviors verified by hand during the 2026-07 memory
# rebuild so they don't silently regress.
#
# HERMETIC IS THE POINT, not a nicety. These tools read and write the
# developer's real memory store, the real gstack learnings, and the real gbrain
# index. An assertion aimed at those is three separate bugs at once: it reads
# state another process (the capture-on-end worker) mutates concurrently, so it
# flakes; it produces a different verdict on every machine, so a failure cannot
# be reproduced; and a guard watching a directory the run never touches passes
# identically whether the code works or not. Section 6 is the guard that keeps
# it that way — read it before adding an assertion here.
#
# Usage: test/smoke.sh   (exit 0 = all pass, 1 = a failure)
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$DIR/test/smoke.sh"
BIN="$DIR/bin"; HOOKS="$DIR/hooks"
pass=0; fail=0
ok()   { printf '  \033[92mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[95mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
# An assertion is judged by ITS OWN exit status, never by the exit status of
# whatever fed it. `set -o pipefail` is right for the tools under test and wrong
# for the checks: in `printf ... | grep -q PATTERN`, -q exits on the first match
# and printf takes SIGPIPE, so the pipeline carries printf's SIGPIPE status
# instead of grep's verdict and a MATCH is reported as a failed check —
# nondeterministically, depending on which side of the pipe wins the race. Two
# runs of this suite went red on `printf '%s\n' "${ROUTE_CORPUS[@]}" | grep -qx
# README.md` with README.md plainly in the list, a third on a --help check, and
# §7k rewrote its own block to read a file instead — one instance of a class
# left open in every other block. Hundreds of assertions here are pipelines, so
# the fix belongs in the one helper they all pass through, once, here.
#
# It cannot hide a real failure: a genuine mismatch fails grep itself, which
# fails the check with or without pipefail. pipefail only ever ADDED failures.
#
# The `_rc` dance is not decoration either. Dozens of assertions here are spelled
# `check "..." "[ \$? -eq 4 ]"` — a DEFERRED `$?` meant to read the status of the
# command the caller ran just before. `set` is itself a command, so touching
# pipefail on the way in would reset `$?` to 0 and turn every one of those into a
# silent pass. Capture it first, re-establish it, then evaluate.
#
# Both contracts are asserted in section 0 below, before anything else runs: a
# bug in this function does not fail a test, it turns tests into silent passes.
check(){
  local _rc=$?
  set +o pipefail
  ( exit "$_rc" )
  if eval "$2"; then set -o pipefail; ok "$1"; else set -o pipefail; bad "$1"; fi
}

echo "== 0. the harness tests itself =="
# `check` is the ONE function every assertion in this file passes through, so a
# bug in it does not fail a test — it turns tests into silent passes, which is
# the worst outcome a suite can have. It has just been changed (pipefail is now
# off for the duration of an assertion), and the first version of that change
# clobbered the DEFERRED `$?` that dozens of assertions below rely on: the
# spelling `check "..." "[ $? -eq 4 ]"` reads the status of the command the
# caller ran a line earlier, and any command run inside `check` before the eval
# resets it to 0. That turned 33 real assertions green while asserting nothing.
# So both of the helper's contracts are asserted here, before anything else runs.
# Each probe runs in a subshell with its own counters, so the deliberate failure
# never reaches the suite's own tally or its output.
h_false=$( pass=0; fail=0; check "probe" "false" >/dev/null; echo "$fail" )
check "HARNESS: a false assertion really fails" "[ \"$h_false\" = 1 ]"
h_true=$( pass=0; fail=0; check "probe" "true" >/dev/null; echo "$pass" )
check "HARNESS: ...and a true one really passes" "[ \"$h_true\" = 1 ]"
h_rc7=$( pass=0; fail=0; (exit 7); check "probe" "[ \$? -eq 7 ]" >/dev/null; echo "$pass" )
check "HARNESS: a deferred \$? reaches the assertion intact" "[ \"$h_rc7\" = 1 ]"
h_rc0=$( pass=0; fail=0; (exit 0); check "probe" "[ \$? -eq 7 ]" >/dev/null; echo "$pass" )
check "HARNESS: ...and is read, not assumed" "[ \"$h_rc0\" = 0 ]"
h_pipe=$( pass=0; fail=0; check "probe" "printf 'a\nb\nc\n' | grep -q a" >/dev/null; echo "$pass" )
check "HARNESS: a 'cmd | grep -q' assertion reports grep's verdict" "[ \"$h_pipe\" = 1 ]"

# ── The sandbox ──────────────────────────────────────────────────────
# One throwaway $HOME for the WHOLE file, exported before the first assertion.
# Every tool under test derives its stores from $HOME — the native memory root
# ($HOME/.claude/projects), the gstack learnings root ($HOME/.gstack/projects),
# the slug resolver and the gbrain repo-policy CLI (both under
# $HOME/.claude/skills/gstack/bin) — so redirecting $HOME once makes the whole
# suite hermetic BY CONSTRUCTION rather than one assertion at a time. That
# distinction is the lesson of this file's own history: the fixture was built
# for the write assertion in section 4 and not carried twenty lines up, leaving
# the Layer-B block reading the developer's live store in the very change whose
# purpose was hermeticity. A per-assertion fixture is only ever as wide as the
# assertion that prompted it.
SANDBOX=$(mktemp -d)
export HOME="$SANDBOX/home"
mkdir -p "$HOME"
trap 'rm -rf "$SANDBOX"' EXIT

echo "== 1. syntax =="
for f in "$BIN"/jjstack-memory-bridge "$BIN"/jjstack-memory-to-learnings \
         "$BIN"/jjstack-capture-write "$BIN"/jjstack-capture-flush \
         "$BIN"/jjstack-global-learn "$BIN"/jjstack-gbrain-phi-lib.sh \
         "$BIN"/jjstack-capture-review-refs "$BIN"/jjstack-number-lines \
         "$BIN"/jjstack-review-preflight "$BIN"/jjstack-review-tooling-sweep \
         "$BIN"/jjstack-review-blast-radius "$BIN"/jjstack-review-intent \
         "$BIN"/jjstack-review-prior-dismissals \
         "$BIN"/jjstack-review-sweep "$BIN"/jjstack-review-autofix-diff \
         "$BIN"/jjstack-review-calibration "$BIN"/jjstack-review-run-report \
         "$BIN"/jjstack-review-vocab.sh "$BIN"/jjstack-review-memory-migrate \
         "$BIN"/jjstack-review-ledger "$BIN"/jjstack-review-revert-history \
         "$BIN"/jjstack-review-dep-inventory \
         "$HOOKS"/shared-memory.sh "$HOOKS"/capture-on-end.sh; do
  check "bash -n $(basename "$f")" "bash -n '$f' 2>/dev/null"
done
# ast.parse, not py_compile: py_compile drops a __pycache__ into bin/.
for f in "$BIN"/jjstack-review-normalize "$BIN"/jjstack-review-baseline; do
  check "python -n $(basename "$f")" \
    "python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' '$f' 2>/dev/null"
done

echo "== 2. PHI lib (pure functions) =="
# reconstruct_cwd against a FIXTURE tree, asserted by equality. The old version
# fed it the developer's own dashed key and accepted `[ -d "$cwd" ]`, which is
# true for almost any resolution and false only on a machine without that
# checkout — an assertion that could neither fail here nor run elsewhere.
RCROOT=$(mktemp -d); mkdir -p "$RCROOT/probe-proj"
git -C "$RCROOT/probe-proj" init -q >/dev/null 2>&1
RCKEY=$(printf '%s' "$RCROOT/probe-proj" | sed 's|/|-|g')
( source "$BIN/jjstack-gbrain-phi-lib.sh"
  [ "$(reconstruct_cwd "$RCKEY")" = "$RCROOT/probe-proj" ]
) && ok "reconstruct_cwd resolves a dashed key back to its git root" \
   || bad "reconstruct_cwd resolves a dashed key back to its git root"
# Control: the resolver must not simply echo its input back dash-for-slash. A
# key with no directory behind it resolves to something that does NOT exist.
( source "$BIN/jjstack-gbrain-phi-lib.sh"
  [ ! -d "$(reconstruct_cwd "-no-such-root-xyzzy-nope")" ]
) && ok "reconstruct_cwd does not invent a live path (control)" \
   || bad "reconstruct_cwd does not invent a live path (control)"
rm -rf "$RCROOT"

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
# This used to run only when the developer's own mychart-sync memory store was
# present and SKIP everywhere else — so the one gate that keeps medical records
# off a shared index was untested on every machine but one, and tested there by
# reading those very records. A fixture PHI project asserts the same refusal
# unconditionally, and reads nobody's data.
#
# The bridge health-checks gbrain before doing anything (`gbrain doctor --fast`)
# and a real gbrain is not operational under a sandbox $HOME, so the stub stands
# in for it — the refusal under test is the PHI gate, not gbrain's health.
BSTUB=$(mktemp -d); printf '#!/bin/sh\nexit 0\n' > "$BSTUB/gbrain"; chmod +x "$BSTUB/gbrain"
mkdir -p "$HOME/.claude/projects/-fixture-phi-proj/memory"
: > "$HOME/.claude/projects/-fixture-phi-proj/memory/.no-gbrain"
printf -- '---\nname: fixture\n---\n\nbody\n' > "$HOME/.claude/projects/-fixture-phi-proj/memory/fixture.md"
PATH="$BSTUB:$PATH" "$BIN/jjstack-memory-bridge" --slug -fixture-phi-proj --ingest --dry-run >/dev/null 2>&1
check "a PHI-marked project's bridge exits 4" "[ \$? -eq 4 ]"
rm -rf "$BSTUB"

echo "== 4. capture-write dry-run (no writes) =="
LESSON='{"type":"feedback","name":"smoke probe","description":"d","body":"b","pattern_key":"smoke-probe","scope":"project","is_rule":false,"confidence":7,"source":"observed"}'
# The dedup state and the chosen action are read by EXACT MATCH, not substring.
# A pair of `grep -q ran-timeout` + `! grep -q ran-clean` assertions looks like
# two independent facts but is one: LAYER_B is a single value on a single line,
# so the negative can only fail when the positive already has. Equality against
# the extracted value carries both implications and additionally rejects a state
# that merely CONTAINS the expected one. Accepts either emitter — the dry-run
# report and the real capture path print the same state.
dedup_state() { sed -nE 's/^.*gbrain dedup:[[:space:]]+(.+)$/\1/p' <<<"$1" | head -1; }
dry_action()  { sed -nE 's/^\[dry-run\] action:[[:space:]]+(.+)$/\1/p'  <<<"$1" | head -1; }
dry_slug()    { sed -nE 's/^\[dry-run\] canonical slug:[[:space:]]*(.+)$/\1/p' <<<"$1" | head -1; }

# A fixture project, NOT this repo. Aiming these at the live checkout coupled
# them to the developer's memory store (Layer A greps it), to the live git
# remote (PHI gate 2 normalizes it) and to whatever the real gstack resolves the
# slug to. The dashed key and canonical slug are DERIVED with the script's own
# transforms so the expectations cannot drift from the implementation.
FIXP="$SANDBOX/probe-project"; mkdir -p "$FIXP"
FDASH=$(printf '%s' "$FIXP" | sed 's|/|-|g')
FSLUG="${FDASH#-}"; FSLUG_LC="${FSLUG,,}"
FIXMEM="$HOME/.claude/projects/$FDASH/memory"; mkdir -p "$FIXMEM"

out=$(JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
# Herestrings, not `printf | grep`: a pipeline under `pipefail` reports the
# left-hand status too, so an assertion could fail for reasons unrelated to the
# match. A herestring has no pipeline and no such ambiguity.
check "capture-write --dry-run resolves the canonical slug" "[ \"\$(dry_slug \"\$out\")\" = \"\$FSLUG\" ]"
check "capture-write --dry-run marks output dry-run" "grep -q '\\[dry-run\\]' <<<\"\$out\""
check "capture-write --dry-run names WHY the layer was skipped" "[ \"\$(dedup_state \"\$out\")\" = 'not-run:pinned' ]"

# Positive control: without the pin Layer B must actually run, or the pin above
# proves nothing and we have quietly stopped testing the real path. Uses a STUB
# gbrain on PATH rather than the real one — the control stays hermetic, instant,
# and works on a machine with no gbrain installed.
STUB=$(mktemp -d)
printf '#!/bin/sh\nexit 0\n' > "$STUB/gbrain"; chmod +x "$STUB/gbrain"
out_live=$(PATH="$STUB:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "gbrain layer runs when not pinned (control)" "[ \"\$(dedup_state \"\$out_live\")\" = 'ran-clean' ]"
# And the pin must beat an available gbrain, not merely an absent one.
out_pin=$(PATH="$STUB:$PATH" JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "pin overrides an available gbrain" "[ \"\$(dedup_state \"\$out_pin\")\" = 'not-run:pinned' ]"

# ── "ran-clean" has TWO halves, and only one of them was ever tested ──
# Per the code's own comment, ran-clean means the query completed AND ITS ANSWER
# WAS USED. Every stub above returns empty stdout, so `local_top` was always
# empty and the parse → score → learnings-resolve block was never reached: the
# sed extraction, the 0.85 threshold and the MERGE_FILE assignment could all be
# deleted and this section stayed green. A stub that returns a real hit is the
# difference between certifying the LABEL and testing the BEHAVIOUR.
#
# Layer A must miss so Layer B is the thing under test, so the merge target
# lives OUTSIDE the memory dir Layer A greps; the learnings row is what resolves
# it, which is exactly the path being exercised.
TARGET="$SANDBOX/prior-lesson.md"
printf -- '---\nname: prior\npattern_key: some-other-key\n---\n\nprior body\n' > "$TARGET"
mkdir -p "$HOME/.gstack/projects/$FSLUG"
printf '{"key":"smoke-probe","files":["%s"]}\n' "$TARGET" > "$HOME/.gstack/projects/$FSLUG/learnings.jsonl"
mkstub() { # mkstub <dir> <line-to-print>
  { printf '#!/bin/sh\n'; printf "printf '%%s\\\\n' '%s'\n" "$2"; } > "$1/gbrain"; chmod +x "$1/gbrain"
}
HIT=$(mktemp -d); mkstub "$HIT" "[0.91] $FSLUG_LC/smoke-probe -- a near duplicate"
out_hit=$(PATH="$HIT:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "a scored gbrain hit is parsed and MERGED into the resolved file" "[ \"\$(dry_action \"\$out_hit\")\" = \"MERGE into \$TARGET\" ]"
check "the answered query still reports ran-clean" "[ \"\$(dedup_state \"\$out_hit\")\" = 'ran-clean' ]"
# Control on the THRESHOLD: below 0.85 is not a duplicate. Without this, raising
# the threshold to 99 — semantic dedup disabled outright — changes nothing.
LOW=$(mktemp -d); mkstub "$LOW" "[0.42] $FSLUG_LC/smoke-probe -- a weak match"
out_low=$(PATH="$LOW:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "a below-threshold hit does NOT merge (control)" "[ \"\$(dry_action \"\$out_low\")\" = 'CREATE new memory' ]"
# Control on the PROJECT SCOPE: Layer B considers this project's pages only. A
# high-scoring page under someone else's slug must not merge into this one.
FOREIGN=$(mktemp -d); mkstub "$FOREIGN" "[0.99] some-other-project/smoke-probe -- not ours"
out_foreign=$(PATH="$FOREIGN:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "a hit under another project's slug does NOT merge (control)" "[ \"\$(dry_action \"\$out_foreign\")\" = 'CREATE new memory' ]"
rm -rf "$HIT" "$LOW" "$FOREIGN"

# A HUNG gbrain must not report as a clean run. This is the failure the whole
# observability exists to expose: timeout kills the query, stderr is discarded,
# the result is empty — which is indistinguishable from "no duplicate found"
# unless the state says so. Stub sleeps past the deadline.
# The deadline is configurable so this costs 1s, not 8 — a test that makes the
# suite slow is a test people stop running.
HANG=$(mktemp -d)
printf '#!/bin/sh\nsleep 30\n' > "$HANG/gbrain"; chmod +x "$HANG/gbrain"
out_hang=$(PATH="$HANG:$PATH" JJSTACK_CAPTURE_GBRAIN_TIMEOUT=1 "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "a timed-out gbrain query reports exactly ran-timeout" "[ \"\$(dedup_state \"\$out_hang\")\" = 'ran-timeout' ]"

# A timeout is only ONE way the query fails. A corrupt or unreadable index (1),
# timeout(1) itself failing on a bad deadline (125), a non-executable (126) or a
# vanished binary (127) all produce the same empty stdout on the same
# stderr-discarded path — so believing any of them is the identical bug, and the
# fix that disbelieved only 124 left the rest reporting ran-clean.
ERR=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$ERR/gbrain"; chmod +x "$ERR/gbrain"
out_err=$(PATH="$ERR:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "a failing gbrain query reports exactly ran-error:1" "[ \"\$(dedup_state \"\$out_err\")\" = 'ran-error:1' ]"
# Positive control on the CODE, not just the state: a different failure must
# report a different rc, or the state could be a constant that happens to match.
printf '#!/bin/sh\nexit 3\n' > "$ERR/gbrain"
out_err3=$(PATH="$ERR:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "the failing query's exit code is carried through (control)" "[ \"\$(dedup_state \"\$out_err3\")\" = 'ran-error:3' ]"
# Positive control on the WHOLE branch: ran-error must be a DISCRIMINATION, not
# a blanket refusal. This has to be a FRESH run of the clean stub — re-grepping
# the output captured before the error stubs existed re-asserts an earlier line
# and observes nothing about the branch it claims to control.
out_clean2=$(PATH="$STUB:$PATH" "$BIN/jjstack-capture-write" --cwd "$FIXP" --dry-run --lesson "$LESSON" 2>&1)
check "a clean query re-run after the failures still reports ran-clean (control)" "[ \"\$(dedup_state \"\$out_clean2\")\" = 'ran-clean' ]"
rm -rf "$HANG" "$STUB" "$ERR"

# The section is named "no writes" but only ever checked stdout. Assert the
# actual claim: a --dry-run leaves the memory dir untouched.
#
# The watched dir must be DERIVED, not baked. An earlier version hardcoded the
# developer's own memory path while the script derives its dir from the --cwd it
# is given. Run from any other checkout the two never coincide, so `ls | wc -l`
# counted an unrelated directory identically before and after and the guard
# could not fail; run from that one clone it read the user's LIVE memory store,
# which the capture-on-end worker writes to concurrently, so it flaked. A guard
# that cannot fire, in the section whose whole point is hermeticity.
#
# Its own project, separate from the Layer-B one above, because the positive
# control below performs a REAL write and marks the project PHI-opted-out: the
# PHI gate stops the run at the native .md, so nothing reaches gstack, gbrain or
# the user's stores. Hermetic, and it exercises the real path.
WP="$SANDBOX/write-project"; mkdir -p "$WP"
WDASH=$(printf '%s' "$WP" | sed 's|/|-|g')
WMEM="$HOME/.claude/projects/$WDASH/memory"
mkdir -p "$WMEM"; : > "$WMEM/.no-gbrain"
before=$(ls -1 "$WMEM" 2>/dev/null | wc -l)
JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" \
    --cwd "$WP" --dry-run --lesson "$LESSON" >/dev/null 2>&1
after=$(ls -1 "$WMEM" 2>/dev/null | wc -l)
check "capture-write --dry-run writes no memory file" "[ \"\$before\" = \"\$after\" ]"
# POSITIVE CONTROL: the same call WITHOUT --dry-run must move that count. If it
# does not, the assertion above is watching a directory the script never touches
# and proves nothing — which is exactly how the baked path passed everywhere.
out_real=$(JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" \
    --cwd "$WP" --lesson "$LESSON" 2>&1)
wrote=$(ls -1 "$WMEM" 2>/dev/null | wc -l)
check "the no-write guard watches the dir the script writes (control)" "[ \"\$wrote\" -gt \"\$after\" ]"
# The dedup state is not a --dry-run curiosity. The REAL path is where a hung or
# broken gbrain silently costs you semantic dedup — in the background capture
# worker, where nobody is watching — so it must say which layers ran there too.
check "a real (non-dry-run) capture reports which dedup layers ran" "[ \"\$(dedup_state \"\$out_real\")\" = 'not-run:phi-optout' ]"

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
# Materialised, never piped into `grep -q`: under `set -o pipefail` grep exits
# on its first match, git takes SIGPIPE, and the pipeline reports 141. Green or
# red by timing — and on a negated check a dead upstream reads as a pass.
git -C "$FX" diff HEAD~1 > "$PF/fx.diff"
check "decoy symbols really are in the diff" \
      "grep -q 'class DocOnlySymbol' '$PF/fx.diff' && grep -q 'type CommentOnlySymbol' '$PF/fx.diff'"
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
git -C "$ENC" diff HEAD~1 > "$ENC/enc.diff"
check "the class definition line is untouched in the diff" \
      "! grep -qE '^[+-]class OrderStatus' '$ENC/enc.diff'"
check "the changed line really is inside the class body" \
      "grep -qE '^\\+    CLOSED' '$ENC/enc.diff'"
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
# `#42` also appears verbatim in the commit dump this artifact ALWAYS emits, so
# grepping the whole file passes against a completely dead extractor. Scope the
# assertion to the section the extractor is the only thing that populates.
awk '/^## Referenced issues$/{s=1;next} /^## /{s=0} s' "$PF/it/intent.md" > "$PF/it-issues.md"
check "intent extracts the referenced issue" "grep -q '#42' '$PF/it-issues.md'"
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

# The orchestrator runs pass 4 with no --reader, so it resolves the default
# $HOME/.claude/skills/gstack/bin/gstack-review-read. Under the suite-wide
# sandbox that path does not exist, and pass 4 correctly exits 3 without
# writing its artifact — which is exactly how this assertion used to "pass":
# by reading the developer's real gstack install. Stub the reader inside the
# sandbox so the orchestrator has a deterministic, offline pass 4 to run. An
# empty history is still a history: pass 4 must produce its artifact.
STUBBIN="$HOME/.claude/skills/gstack/bin"; mkdir -p "$STUBBIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBBIN/gstack-review-read"
chmod +x "$STUBBIN/gstack-review-read"
check "the sandbox reader stub is in place (control)" "[ -x '$STUBBIN/gstack-review-read' ]"

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

echo "== 5d. round 2: no row may claim more than the artifact under it =="
# Round 1 fixed the false-green in rows 1 and 5 — exactly as wide as the
# fixture that found it. Rows 2, 3 and 4 still read a bare exit code, so an
# unresolvable --base printed "ran — map built" and "ran — claim gathered"
# over an empty map and an intent.md calling a fully committed change
# uncommitted. The class, not the instance: every row is rendered from a fact
# the pass wrote down, and no pass accepts a base it could not resolve.

# --- an unresolvable --base is a named error, never a silent empty diff -----
"$BIN/jjstack-review-preflight" --out "$PF/badbase" --repo "$FX" --base orgin/main \
  > "$PF/badbase.out" 2>&1; rc=$?
check "an unresolvable --base fails the pre-flight" "[ $rc -ne 0 ]"
check "the error names the ref that could not be resolved" \
      "grep -q 'orgin/main' '$PF/badbase.out'"
check "no evidence pack is written from an unresolvable base" \
      "[ ! -f '$PF/badbase/EVIDENCE-PACK.md' ]"
# Each sub-pass refuses on its own — the orchestrator is not the only guard.
"$BIN/jjstack-review-blast-radius" --out "$PF/bb2" --repo "$FX" --base orgin/main \
  > "$PF/bb2.out" 2>&1; rc=$?
check "blast-radius refuses an unresolvable --base" "[ $rc -ne 0 ]"
check "blast-radius writes no map from an unresolvable base" \
      "! grep -q 'Empty diff' '$PF/bb2/blast-radius.md' 2>/dev/null"
# The error must name the BASE as the problem. Letting a downstream `git diff`
# failure surface instead still exits non-zero, but sends the reader hunting a
# symptom rather than the typo they made.
check "blast-radius diagnoses the ref, not a downstream symptom" \
      "grep -q 'does not resolve to a commit' '$PF/bb2.out'"
"$BIN/jjstack-review-intent" --out "$PF/bb3" --repo "$FX" --base orgin/main \
  > "$PF/bb3.out" 2>&1; rc=$?
check "intent refuses an unresolvable --base" "[ $rc -ne 0 ]"
check "intent never calls a committed change uncommitted" \
      "! grep -q 'the intent is uncommitted' '$PF/bb3/intent.md' 2>/dev/null"
check "intent diagnoses the ref, not a downstream symptom" \
      "grep -q 'does not resolve to a commit' '$PF/bb3.out'"
# Positive control — the identical invocation with a REAL base does build a
# pack, so the assertions above are about the bad ref and not about the fixture.
check "the same invocation with a valid base does build a pack (control)" \
      "[ -f '$PF/pack/EVIDENCE-PACK.md' ]"

# --- rows 2/3/4 are rendered from facts, exactly like rows 1 and 5 ---------
# Base == HEAD: a legitimately empty scope. The passes ran and exited 0, so an
# rc-derived row says "map built" / "claim gathered" over nothing at all.
"$BIN/jjstack-review-preflight" --out "$PF/empty" --repo "$FX" --base HEAD >/dev/null 2>&1
check "row 2 does not claim a map was built over an empty diff" \
      "! grep -qE '^\| 2 .*ran — map built' '$PF/empty/EVIDENCE-PACK.md'"
check "row 2 agrees with blast-radius.md" \
      "grep -q 'Empty diff' '$PF/empty/blast-radius.md'"
check "row 3 does not claim a claim was gathered when none was found" \
      "! grep -qE '^\| 3 .*ran — claim gathered' '$PF/empty/EVIDENCE-PACK.md'"
check "row 3 agrees with intent.md" \
      "grep -q 'the intent is uncommitted' '$PF/empty/intent.md'"
# Positive controls — both rows CAN say it, on the fixture where it is true.
check "row 2 says a map was built when symbols really were mapped (control)" \
      "grep -qE '^\| 2 .*map built' '$PF/pack/EVIDENCE-PACK.md'"
check "row 3 says a claim was gathered when commits really were read (control)" \
      "grep -qE '^\| 3 .*claim gathered' '$PF/pack/EVIDENCE-PACK.md'"

# --- row 1 must read TOOLS_PASSED, not just DETECTED/FAILED/ERRORED --------
# A detected-but-skipped runner falls to the else arm: "ran — no failures" over
# TOOLS_PASSED=0, one row above row 5 saying NO baseline exists.
NOR="$PF/nothing-ran"; mkdir -p "$NOR"
git -C "$NOR" init -q -b main 2>/dev/null
git -C "$NOR" config user.email t@t; git -C "$NOR" config user.name T
printf 'test:\n\t@true\n' > "$NOR/Makefile"
git -C "$NOR" add -A >/dev/null 2>&1; git -C "$NOR" commit -qm seed >/dev/null 2>&1
"$BIN/jjstack-review-preflight" --out "$NOR/pack" --repo "$NOR" --base HEAD --skip-tests >/dev/null 2>&1
check "the no-tools-ran fixture really detects exactly one tool (control)" \
      "grep -q '^TOOLS_DETECTED=1' '$NOR/pack/tooling-status.env' && grep -q '^TOOLS_PASSED=0' '$NOR/pack/tooling-status.env'"
check "row 1 does not say 'no failures' when nothing ran" \
      "! grep -qE '^\| 1 .*ran — no failures' '$NOR/pack/EVIDENCE-PACK.md'"
check "row 1 and row 5 agree that nothing was proven" \
      "grep -qE '^\| 5 .*NO baseline exists' '$NOR/pack/EVIDENCE-PACK.md'"
# Positive control — "ran — no failures" is a real shipped string that DOES
# fire when tools really passed, so the assertion above is not vacuous.
check "row 1 says 'ran — no failures' when tools really passed (control)" \
      "grep -qE '^\| 1 .*ran — no failures' '$PF/pack/EVIDENCE-PACK.md'"

# --- the results table must not invent a runner that was never detected ----
"$BIN/jjstack-review-tooling-sweep" --out "$PF/noskip" --repo "$BARE" --skip-tests >/dev/null 2>&1
check "a runner-less repo never renders a skipped test runner" \
      "! grep -q 'skipped (--skip-tests)' '$PF/noskip/tooling-results.md'"
check "the results table agrees with TEST_STATUS=none" \
      "grep -q '^TEST_STATUS=none' '$PF/noskip/tooling-status.env'"
# Positive control — with a real runner the same flag DOES render skipped.
check "with a real runner --skip-tests really does render skipped (control)" \
      "grep -q 'skipped (--skip-tests)' '$PF/pack3/tooling-results.md'"
check "and names the runner it did not run" \
      "grep -qF 'test/smoke.sh' '$PF/pack3/tooling-results.md'"

# --- every interpolation site, not just the two that were reported --------
# Round 1 removed raw interpolation from the `node -e` probe and left a
# `sed "s|^$REPO/||"` in the same file. A repo path holding a sed metacharacter
# makes the strip abort for every symbol, refs drops to 0, and the report
# AFFIRMATIVELY prints "Contained — no out-of-diff references" for a symbol
# with a live stale caller. Worse than no map: containment as evidence.
BRK="$PF/br[ack|et"; mkdir -p "$BRK/lib"
git -C "$BRK" init -q -b main 2>/dev/null
git -C "$BRK" config user.email t@t; git -C "$BRK" config user.name T
printf '#!/usr/bin/env bash\ncompute_total() { echo 1; }\n' > "$BRK/lib/core.sh"
printf '#!/usr/bin/env bash\n. lib/core.sh\ncompute_total\n' > "$BRK/consumer.sh"
git -C "$BRK" add -A >/dev/null 2>&1; git -C "$BRK" commit -qm seed >/dev/null 2>&1
printf '#!/usr/bin/env bash\ncompute_grand_total() { echo 1; }\n' > "$BRK/lib/core.sh"
git -C "$BRK" add -A >/dev/null 2>&1; git -C "$BRK" commit -qm rename >/dev/null 2>&1
"$BIN/jjstack-review-blast-radius" --out "$BRK/out" --repo "$BRK" --base HEAD~1 >/dev/null 2>&1
check "a sed-metacharacter repo path still finds the stale caller" \
      "grep -q 'consumer.sh' '$BRK/out/blast-radius.md'"
sed -n '/^## Contained/,/^---$/p' "$BRK/out/blast-radius.md" > "$PF/brk-contained.md"
check "and never affirms containment over a live caller" \
      "! grep -q 'compute_total' '$PF/brk-contained.md'"
# Positive control, recovered from git rather than invented: the exact
# expression this file shipped -- sed "s|^$REPO/||" -- genuinely aborts on
# this path, so the two assertions above are about the fix and not the fixture.
REPO="$BRK"
printf '%s/consumer.sh:2:x\n' "$BRK" | sed "s|^$REPO/||" > "$PF/oldsed.out" 2>/dev/null
unset REPO
check "the shipped raw interpolation genuinely breaks on this path (control)" \
      "! grep -q '^consumer.sh' '$PF/oldsed.out'"
# The SAME class at the --also-repo site: prefix AND replacement are spliced.
SIB="$PF/si|bling"; mkdir -p "$SIB"
printf '#!/usr/bin/env bash\ncompute_total\n' > "$SIB/caller.sh"
"$BIN/jjstack-review-blast-radius" --out "$PF/sibout" --repo "$FX" --base HEAD~1 \
   --also-repo "$SIB" >/dev/null 2>&1
check "--also-repo with a metacharacter path still lists the sibling caller" \
      "grep -q 'caller.sh' '$PF/sibout/blast-radius.md'"
check "the sibling site is labelled with its repo name" \
      "grep -qF '(si|bling)' '$PF/sibout/blast-radius.md'"
# Positive control — a plain sibling path is listed too, so the assertions
# above test the metacharacter and not --also-repo being wired up at all.
PLAINSIB="$PF/plainsib"; mkdir -p "$PLAINSIB"
printf '#!/usr/bin/env bash\ncompute_total\n' > "$PLAINSIB/caller.sh"
"$BIN/jjstack-review-blast-radius" --out "$PF/plainsibout" --repo "$FX" --base HEAD~1 \
   --also-repo "$PLAINSIB" >/dev/null 2>&1
check "a plain --also-repo path is listed (control)" \
      "grep -qF '(plainsib)' '$PF/plainsibout/blast-radius.md'"

# --- the comment filter the reference doc claims, in a real language -------
# The shell decoy above passes for the wrong reason: shell files have keyword
# extraction disabled outright, so nothing there exercises a comment filter.
# references/review-preflight.md states comment lines are never mined; test the
# claim where the keywords are actually live.
CMT="$PF/cmt"; mkdir -p "$CMT"
git -C "$CMT" init -q -b main 2>/dev/null
git -C "$CMT" config user.email t@t; git -C "$CMT" config user.name T
printf 'def alpha():\n    return 1\n' > "$CMT/core.py"
printf 'class Widget {}\n' > "$CMT/mod.js"
printf 'from core import alpha\nprint(alpha())\nprint("PyCommentDecoy")\nprint("JsCommentDecoy")\nprint("RealPySymbol")\n' > "$CMT/user.py"
git -C "$CMT" add -A >/dev/null 2>&1; git -C "$CMT" commit -qm seed >/dev/null 2>&1
printf 'def alpha():\n    return 2\n# class PyCommentDecoy\ndef RealPySymbol():\n    return 3\n' > "$CMT/core.py"
printf 'class Widget {}\n// class JsCommentDecoy\n' > "$CMT/mod.js"
git -C "$CMT" add -A >/dev/null 2>&1; git -C "$CMT" commit -qm change >/dev/null 2>&1
"$BIN/jjstack-review-blast-radius" --out "$CMT/out" --repo "$CMT" --base HEAD~1 >/dev/null 2>&1
check "a whole-line # comment in a .py diff declares no symbol" \
      "! grep -q 'PyCommentDecoy' '$CMT/out/blast-radius.md'"
check "a whole-line // comment in a .js diff declares no symbol" \
      "! grep -q 'JsCommentDecoy' '$CMT/out/blast-radius.md'"
# Positive controls — a filter that deletes everything would also pass those.
check "a real definition on a real code line IS still mined (control)" \
      "grep -q 'RealPySymbol' '$CMT/out/blast-radius.md'"
git -C "$CMT" diff HEAD~1 > "$CMT/cmt.diff"
check "both decoys really are in the diff (control)" \
      "grep -q '# class PyCommentDecoy' '$CMT/cmt.diff' && grep -q '// class JsCommentDecoy' '$CMT/cmt.diff'"
check "both decoys really are referenced outside the diff (control)" \
      "grep -q 'PyCommentDecoy' '$CMT/user.py' && grep -q 'JsCommentDecoy' '$CMT/user.py'"

# --- the re-entrancy guard must SUPPRESS, not just print a banner ----------
# Deleting `TEST=""` from the guard left the old assertion fully green: it only
# grepped the --dry-run banner, never that the suite did not run. Assert the
# side effect instead — the command's own sentinel file.
RNT="$PF/reent"; mkdir -p "$RNT"
git -C "$RNT" init -q -b main 2>/dev/null
git -C "$RNT" config user.email t@t; git -C "$RNT" config user.name T
printf 'seed\n' > "$RNT/f.txt"
git -C "$RNT" add -A >/dev/null 2>&1; git -C "$RNT" commit -qm seed >/dev/null 2>&1
JJSTACK_REVIEW_PREFLIGHT=1 "$BIN/jjstack-review-tooling-sweep" --out "$PF/rg1" \
  --repo "$RNT" --typecheck none --lint none --test "touch $PF/test-ran-guarded" >/dev/null 2>&1
check "the re-entrancy guard does not execute the test command" \
      "[ ! -f '$PF/test-ran-guarded' ]"
check "and records the suite as skipped, not passed" \
      "grep -q '^TEST_STATUS=skipped' '$PF/rg1/tooling-status.env'"
# The guard covers only $TEST today; `make lint` re-enters just as readily.
JJSTACK_REVIEW_PREFLIGHT=1 "$BIN/jjstack-review-tooling-sweep" --out "$PF/rg2" \
  --repo "$RNT" --typecheck none --lint "touch $PF/lint-ran-guarded" --test none >/dev/null 2>&1
check "the re-entrancy guard suppresses the linter too" \
      "[ ! -f '$PF/lint-ran-guarded' ]"
check "and records the linter as skipped" \
      "grep -q '^LINT_STATUS=skipped' '$PF/rg2/tooling-status.env'"
# "we chose not to run it" and "the guard stopped it" are different facts, and
# a row that hardcodes one reason prints the wrong one for the other.
check "a guard-skipped row names the guard, not --skip-tests" \
      "grep -q 'skipped (re-entrancy guard)' '$PF/rg1/tooling-results.md'"
check "and still names the command it did not run" \
      "! grep -qE '^\| test \| .n/a. \|' '$PF/rg1/tooling-results.md'"
# Positive controls — the identical commands DO run without the guard, so the
# assertions above prove suppression rather than a broken invocation.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/rg3" --repo "$RNT" \
  --typecheck none --lint none --test "touch $PF/test-ran-free" >/dev/null 2>&1
check "the same test command really runs without the guard (control)" \
      "[ -f '$PF/test-ran-free' ]"
"$BIN/jjstack-review-tooling-sweep" --out "$PF/rg4" --repo "$RNT" \
  --typecheck none --lint "touch $PF/lint-ran-free" --test none >/dev/null 2>&1
check "the same lint command really runs without the guard (control)" \
      "[ -f '$PF/lint-ran-free' ]"

# --- --max-symbols was added for a round-1 finding with no test at all -----
MS="$PF/maxsym"; mkdir -p "$MS"
git -C "$MS" init -q -b main 2>/dev/null
git -C "$MS" config user.email t@t; git -C "$MS" config user.name T
printf 'def s_one():\n    pass\n' > "$MS/core.py"
printf 'import core\ncore.s_one(); core.s_two(); core.s_three(); core.s_four(); core.s_five()\n' > "$MS/user.py"
git -C "$MS" add -A >/dev/null 2>&1; git -C "$MS" commit -qm seed >/dev/null 2>&1
printf 'def s_one():\n    pass\ndef s_two():\n    pass\ndef s_three():\n    pass\ndef s_four():\n    pass\ndef s_five():\n    pass\n' > "$MS/core.py"
git -C "$MS" add -A >/dev/null 2>&1; git -C "$MS" commit -qm more >/dev/null 2>&1
"$BIN/jjstack-review-blast-radius" --out "$MS/cap" --repo "$MS" --base HEAD~1 --max-symbols 2 >/dev/null 2>&1
check "--max-symbols announces the truncation" \
      "grep -q 'TRUNCATED' '$MS/cap/blast-radius.md'"
check "--max-symbols names how many of how many were mapped" \
      "grep -q 'only the first 2 of' '$MS/cap/blast-radius.md'"
check "--max-symbols really stops after N symbols" \
      "[ \$(grep -c '^### .' '$MS/cap/blast-radius.md') -eq 2 ]"
# Positive control — the same fixture without the cap maps them all, so the
# assertions above are about the flag and not about a small diff.
"$BIN/jjstack-review-blast-radius" --out "$MS/all" --repo "$MS" --base HEAD~1 >/dev/null 2>&1
check "without --max-symbols the same fixture maps every symbol (control)" \
      "! grep -q 'TRUNCATED' '$MS/all/blast-radius.md' && [ \$(grep -c '^### .' '$MS/all/blast-radius.md') -eq 5 ]"

# --- the documented non-executing path must exist at the documented entry --
# SKILL.md tells the reader to run the sweep with --typecheck/--lint/--test
# none on a tree they do not trust; the orchestrator it tells them to run
# rejected all three as unknown args.
"$BIN/jjstack-review-preflight" --out "$PF/notrust" --repo "$FX" --base HEAD~1 \
  --typecheck none --lint none --test none > "$PF/notrust.out" 2>&1; rc=$?
check "preflight accepts the documented non-executing flags" "[ $rc -ne 2 ]"
check "the non-executing path detects no tooling to run" \
      "grep -q '^TOOLS_DETECTED=0' '$PF/notrust/tooling-status.env'"
check "and leaves all three categories IN SCOPE" \
      "[ \$(grep -c '^## IN SCOPE' '$PF/notrust/exclusions.md') -eq 3 ]"
check "and the index says NOTHING was checked" \
      "grep -qE '^\| 1 .*NOTHING was checked' '$PF/notrust/EVIDENCE-PACK.md'"
# Positive control, recovered from the shipped doc rather than invented.
check "SKILL.md really documents this exact flag set (control)" \
      "grep -qF -- '--typecheck none --lint none --test none' '$DIR/skills/review/SKILL.md'"

# --- the sweep's exit contract -------------------------------------------
# Header: "0 at least one detected tool ran and none reported failures". When
# the only detected tool COULD NOT RUN, nothing ran — 0 contradicts the file's
# own documented contract and reads as a clean sweep to any caller.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/onlyerr" --repo "$FX" \
   --typecheck none --lint none --test 'jjstack-no-such-binary-xyz' >/dev/null 2>&1; rc=$?
check "the sweep does not exit 0 when its only tool COULD NOT RUN" "[ $rc -ne 0 ]"
check "and the artifact says so" \
      "grep -q 'test COULD NOT RUN' '$PF/onlyerr/tooling-results.md'"
# Positive control — a sweep where a tool really ran and passed still exits 0.
"$BIN/jjstack-review-tooling-sweep" --out "$PF/okexit" --repo "$FX" \
   --typecheck none --lint none --test 'true' >/dev/null 2>&1; rc=$?
check "the sweep still exits 0 when a tool really ran and passed (control)" "[ $rc -eq 0 ]"

# --- the changelog is for readers, so its sections must mean what they say -
UNREL="$(awk '/^## \[Unreleased\]/{u=1;next} /^## \[/{u=0} u' "$DIR/CHANGELOG.md")"
printf '%s\n' "$UNREL" > "$PF/unreleased.md"
awk '/^### Fixed$/{f=1;next} /^### /{f=0} f' "$PF/unreleased.md" > "$PF/unrel-fixed.md"
awk '/^### Added$/{f=1;next} /^### /{f=0} f' "$PF/unreleased.md" > "$PF/unrel-added.md"
check "the Unreleased section declares each heading once" \
      "[ \$(grep -c '^### Added$' '$PF/unreleased.md') -le 1 ] && [ \$(grep -c '^### Fixed$' '$PF/unreleased.md') -le 1 ]"
check "the gbrain ran-clean fix is still filed under Fixed" \
      "grep -q 'no longer claims it ran clean' '$PF/unrel-fixed.md'"
check "the pre-flight feature is filed under Added" \
      "grep -q 'gathers evidence before it starts thinking' '$PF/unrel-added.md'"

rm -rf "$PF"
echo "== 5e. number-lines (grounded locations) =="
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

echo "== 5f. review-normalize (finding struct + confidence) =="
# Every finding must arrive as a struct the reader can act on. `remediation`
# is required at EMISSION time precisely because a finding nobody can act on
# is not worth a line in the report.
RN="$(mktemp -d)"
# Round-2 review: `grep confidence badfile` is a tautology — the record echoes
# the offending line verbatim in `raw`, so every diagnostic name is already in
# the file. Assertions about WHAT the tool said must read the `reason` field
# alone; this helper is the only way to do that without matching the echo.
reasons_of(){ python3 -c 'import json,sys
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if line:
        print(json.loads(line)["reason"])' "$1"; }
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
# Read the REASON, never the whole record: `raw` echoes the input line, so a
# grep over the file matches the emitter's own word and not the tool's verdict.
check "the malformed record names the bad field"   \
  "reasons_of '$RN/nullconf.bad.jsonl' | grep -q 'confidence'"
check "the reason names the LINE that poisoned it" \
  "python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readline())[\"line\"])' '$RN/nullconf.bad.jsonl' | grep -qx 2"
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

# PR #16 review ROUND 2 (P1): the round-1 fix was written exactly as wide as its
# fixture. `float(10**400)` raises OverflowError — an ArithmeticError named by
# neither guard — so it escaped the per-finding handler, hit the last-resort
# guard, BROKE the loop, lost the valid P0 on the next line, and never created
# --invalid-out. Reproduced: rc=3, 1 of 2 P0s emitted, bad file MISSING.
BIG="$(printf '9%.0s' $(seq 1 400))"
BIGCONF="{\"lens\":\"security\",\"file\":\"b.py\",\"start_line\":3,\"severity\":\"P0\",\"confidence\":$BIG,\"message\":\"huge conf\",\"quote\":\"q\",\"explanation\":\"e\",\"remediation\":\"r\"}"
printf '%s\n%s\n%s\n' "$P0A" "$BIGCONF" "$P0B" > "$RN/bigconf.jsonl"
rm -f "$RN/bigconf.bad.jsonl"
"$BIN/jjstack-review-normalize" "$RN/bigconf.jsonl" \
  --invalid-out "$RN/bigconf.bad.jsonl" > "$RN/bigconf.out" 2>/dev/null; rc=$?
check "a 400-digit confidence is malformed INPUT, not a crash" "[ $rc -eq 1 ]"
check "both P0s around a huge confidence survive" \
  "[ \"\$(wc -l < '$RN/bigconf.out')\" -eq 2 ]"
check "the P0 AFTER a huge confidence is emitted" "grep -q 'valid p0 two' '$RN/bigconf.out'"
check "the huge confidence IS recorded"          "[ -s '$RN/bigconf.bad.jsonl' ]"
check "its reason names confidence, not a crash" \
  "reasons_of '$RN/bigconf.bad.jsonl' | grep -q 'confidence'"

# The CLASS, not the instance. OverflowError is one exception type; the defect
# is that ANY exception raised while normalizing ONE finding took the whole run
# with it. Inject a fault type nothing in the tool anticipates (ZeroDivisionError
# via a patched normalize_finding) on the MIDDLE line only, and require: the
# other findings survive, the poisoned line is recorded, and the exit code is
# the internal one (3) rather than the malformed one (1).
cat > "$RN/onebad.py" <<'PYEOF2'
import importlib.machinery, importlib.util, json, sys

loader = importlib.machinery.SourceFileLoader("jjnorm", sys.argv[1])
spec = importlib.util.spec_from_loader("jjnorm", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

real = mod.normalize_finding


def selective(obj):
    if isinstance(obj, dict) and obj.get("file") == "b.py":
        return 1 / 0          # a class the tool has never heard of
    return real(obj)


mod.normalize_finding = selective
sys.exit(mod.main(sys.argv[2:]))
PYEOF2
printf '%s\n%s\n%s\n' "$P0A" "$NULLCONF" "$P0B" > "$RN/cls.jsonl"
rm -f "$RN/cls.bad.jsonl"
python3 "$RN/onebad.py" "$BIN/jjstack-review-normalize" "$RN/cls.jsonl" \
  --invalid-out "$RN/cls.bad.jsonl" > "$RN/cls.out" 2>/dev/null; rc=$?
check "an UNANTICIPATED exception exits 3, not 1" "[ $rc -eq 3 ]"
check "an unanticipated exception loses no other finding" \
  "[ \"\$(wc -l < '$RN/cls.out')\" -eq 2 ]"
check "the finding AFTER the poisoned one is emitted" "grep -q 'valid p0 two' '$RN/cls.out'"
check "--invalid-out is written on the internal path" "[ -s '$RN/cls.bad.jsonl' ]"
check "the internal failure names its own line"  \
  "python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readline())[\"line\"])' '$RN/cls.bad.jsonl' | grep -qx 2"
# Positive control — the identical harness with NO poisoned file must pass all
# three, or \"2 survived\" could be the shim rejecting b.py for its own reasons.
printf '%s\n%s\n' "$P0A" "$P0B" > "$RN/cls.ok.jsonl"
python3 "$RN/onebad.py" "$BIN/jjstack-review-normalize" "$RN/cls.ok.jsonl" \
  > "$RN/cls.ok.out" 2>/dev/null; rc=$?
check "positive control: the same shim passes 2 clean findings" \
  "[ $rc -eq 0 ] && [ \"\$(wc -l < '$RN/cls.ok.out')\" -eq 2 ]"

# PR #16 review ROUND 2 (P2): STREAMING had no coverage at all — reverting the
# emit to the pre-fix buffered shape left the whole suite green. Streaming is
# one of the three mechanisms the docstring names, so it gets a test that can
# only pass if it is real: make the run die while reading a LATER line, and
# require the finding validated BEFORE it to be on stdout already. Buffered,
# the list is never printed and stdout is empty.
cat > "$RN/killread.py" <<'PYEOF3'
import importlib.machinery, importlib.util, json, sys

loader = importlib.machinery.SourceFileLoader("jjnorm", sys.argv[1])
spec = importlib.util.spec_from_loader("jjnorm", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

real_loads = json.loads
calls = []


def dying_loads(text, *a, **kw):
    calls.append(text)
    if len(calls) > 1:                     # the SECOND line kills the run
        raise RuntimeError("input died mid-run")
    return real_loads(text, *a, **kw)


json.loads = dying_loads
try:
    sys.exit(mod.main(sys.argv[2:]))
finally:
    json.loads = real_loads
PYEOF3
printf '%s\n%s\n' "$P0A" "$P0B" > "$RN/stream.jsonl"
rm -f "$RN/stream.bad.jsonl"
python3 "$RN/killread.py" "$BIN/jjstack-review-normalize" "$RN/stream.jsonl" \
  --invalid-out "$RN/stream.bad.jsonl" > "$RN/stream.out" 2>/dev/null; rc=$?
check "a finding validated before a fatal error is ALREADY on stdout" \
  "grep -q 'valid p0 one' '$RN/stream.out'"
check "a fatal error mid-run still exits 3" "[ $rc -eq 3 ]"
check "--invalid-out exists even when the run dies" "[ -f '$RN/stream.bad.jsonl' ]"
# Positive control — the same shim on a ONE-line file never reaches the fault,
# so it must exit 0 with that line emitted. Without this, "one line survived"
# could just be the shim mangling the second record.
python3 "$RN/killread.py" "$BIN/jjstack-review-normalize" "$RN/good.jsonl" \
  > "$RN/stream.ok.out" 2>/dev/null; rc=$?
check "positive control: the same shim passes a 1-line file" \
  "[ $rc -eq 0 ] && [ \"\$(wc -l < '$RN/stream.ok.out')\" -eq 1 ]"

# PR #16 review ROUND 2 (P2): --invalid-out was opened only inside `if invalid:`,
# so a clean re-run left the PREVIOUS run's malformed records on disk. The skill
# points a fixed path at this file; a reader who trusts it sees findings that
# were fixed last run. The file must be truthful after EVERY run.
printf '%s\n' "$NULLCONF" > "$RN/dirty.jsonl"
"$BIN/jjstack-review-normalize" "$RN/dirty.jsonl" --invalid-out "$RN/reused.jsonl" \
  >/dev/null 2>&1
check "setup: the dirty run recorded its malformed finding" "[ -s '$RN/reused.jsonl' ]"
"$BIN/jjstack-review-normalize" "$RN/good.jsonl" --invalid-out "$RN/reused.jsonl" \
  >/dev/null 2>&1; rc=$?
check "a clean run exits 0 with --invalid-out"     "[ $rc -eq 0 ]"
check "a clean run TRUNCATES the stale invalid file" "[ ! -s '$RN/reused.jsonl' ]"
check "the stale record is really gone"            "! grep -q 'null conf' '$RN/reused.jsonl'"

# PR #16 review (P2): the non-blank guard only inspected `str`, so a null quote
# and an empty-list remediation walked through the schema gate this file exists
# to enforce — a P1 reaching the report with an uncheckable location.
printf '%s\n' "${GOOD/\"quote\":\"os.system(x)\"/\"quote\":null}" > "$RN/nullquote.jsonl"
rm -f "$RN/nullquote.bad.jsonl"
"$BIN/jjstack-review-normalize" "$RN/nullquote.jsonl" --invalid-out "$RN/nullquote.bad.jsonl" \
  > "$RN/nullquote.out" 2>"$RN/nullquote.err"; rc=$?
check "a null quote is rejected"        "[ $rc -eq 1 ] && [ ! -s '$RN/nullquote.out' ]"
# Same de-tautologising as above: the reason must NAME quote. A grep over the
# whole record passed even when every diagnostic was renamed to gibberish.
check "the null quote is REPORTED"      \
  "reasons_of '$RN/nullquote.bad.jsonl' | grep -q '^empty required field(s): quote$'"
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

echo "== 5g. review-baseline (instance scope — the only rung that may suppress) =="
# The baseline is how a re-review surfaces only NEW issues without losing the
# old ones. Two mechanisms with deliberately different aging: brittle
# fingerprints (edit the source, the finding comes back) and drift-tolerant
# rules (survive rewording, which is why they need a stated reason). Since the
# store consolidation it is TSV, in jjstack/review-memory/, and it is the
# NARROWEST rung of the memory ladder — the only one allowed to suppress.
RB="$(mktemp -d)"
F1='{"lens":"security","file":"a.py","start_line":12,"severity":"P1","confidence":0.75,"message":"shell injection","quote":"os.system(x)","explanation":"e","remediation":"r"}'
F2='{"lens":"perf","file":"b.py","start_line":3,"severity":"P2","confidence":0.4,"message":"n+1 query","quote":"for r in rows: get(r)","explanation":"e2","remediation":"r2"}'
printf '%s\n%s\n' "$F1" "$F2" > "$RB/findings.jsonl"
BL_HDR=$'#jjstack-review-store\tscope=instance\tmax-effect=suppress\tv=3\tjjstack=x'

# Mandatory reason — an unexplained suppression is indistinguishable from a bug.
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" -o "$RB/noreason.tsv" >/dev/null 2>&1; rc=$?
check "generate without --reason exits 2" "[ $rc -eq 2 ]"
check "generate without --reason writes nothing" "[ ! -f '$RB/noreason.tsv' ]"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "accepted in triage" \
  -o "$RB/bl.tsv" >/dev/null 2>&1; rc=$?
check "generate with --reason exits 0" "[ $rc -eq 0 ]"
check "baseline records both fingerprints" "[ \"\$(grep -c 'sha256:' '$RB/bl.tsv')\" -eq 2 ]"
check "every fingerprint carries a reason" "[ \"\$(grep -c 'accepted in triage' '$RB/bl.tsv')\" -eq 2 ]"
# One decision is one line: the whole reason this store is TSV and not JSON is
# that a suppression must read as a one-line PR diff.
check "a suppression is exactly one line" \
  "[ \"\$(grep -c '^fingerprint	' '$RB/bl.tsv')\" -eq 2 ]"
check "the store declares its scope in the header" \
  "head -n 1 '$RB/bl.tsv' | grep -q 'scope=instance'"
check "the store declares its effect ceiling" \
  "head -n 1 '$RB/bl.tsv' | grep -q 'max-effect=suppress'"

"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/bl.tsv" \
  > "$RB/all.out" 2>/dev/null; rc=$?
check "apply exits 0 when nothing is active" "[ $rc -eq 0 ]"
# The core property: suppressed is NOT deleted. Both findings still present.
check "suppressed findings stay in the output" "[ \"\$(wc -l < '$RB/all.out')\" -eq 2 ]"
check "suppression is auditable (reason shown)" "grep -q 'accepted in triage' '$RB/all.out'"
check "suppression names its effect" "grep -q '\"effect\": \"suppress\"' '$RB/all.out'"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/bl.tsv" \
  --active-only > "$RB/active.out" 2>/dev/null
check "--active-only shows just the new stuff" "[ ! -s '$RB/active.out' ]"

# Fingerprints are brittle ON PURPOSE: edit the flagged source, get it back.
printf '%s\n%s\n' "${F1/os.system(x)/os.system(y)}" "$F2" > "$RB/edited.jsonl"
"$BIN/jjstack-review-baseline" apply "$RB/edited.jsonl" --baseline "$RB/bl.tsv" \
  --active-only > "$RB/edited.out" 2>/dev/null; rc=$?
check "editing the quoted line reactivates it" "[ \"\$(wc -l < '$RB/edited.out')\" -eq 1 ]"
check "a reactivated finding exits 1"          "[ $rc -eq 1 ]"
# ...but an unrelated edit ABOVE the finding only shifts start_line, and must not.
printf '%s\n%s\n' "${F1/\"start_line\":12/\"start_line\":40}" "$F2" > "$RB/shifted.jsonl"
"$BIN/jjstack-review-baseline" apply "$RB/shifted.jsonl" --baseline "$RB/bl.tsv" \
  --active-only > "$RB/shifted.out" 2>/dev/null
check "a pure line shift does NOT reactivate"  "[ ! -s '$RB/shifted.out' ]"

# Drift-tolerant glob rules. `-` means "unstated", so it matches anything.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\taccepted-risk\t-\tper*\t-\t-\tpolicy: perf lens is advisory here\n'; } > "$RB/rules.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/rules.tsv" \
  --active-only > "$RB/rules.out" 2>/dev/null; rc=$?
check "glob rule suppresses its lens"       "[ \"\$(wc -l < '$RB/rules.out')\" -eq 1 ]"
check "glob rule leaves other lenses active" "grep -q 'shell injection' '$RB/rules.out'"
# Positive control — the rule guard can actually reject. A malformed-baseline
# check that never fires looks exactly like a clean baseline.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\taccepted-risk\t-\tper*\t-\t-\t-\n'; } > "$RB/noreason-rule.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/noreason-rule.tsv" >/dev/null 2>&1; rc=$?
check "rule without a reason exits 4" "[ $rc -eq 4 ]"
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\taccepted-risk\t-\t-\t-\t-\tbecause\n'; } > "$RB/catchall.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/catchall.tsv" >/dev/null 2>&1; rc=$?
check "reason-only rule exits 4" "[ $rc -eq 4 ]"
# PR #16 review (P1): the guard above only asked whether a field was PRESENT
# and non-empty, so a universal glob sailed through and muted the whole repo at
# exit 0 — the posture table then read "nothing above P3" and emitted APPROVE.
# Reproduced with path "*": 0 active, 2 suppressed, rc=0. Every column
# `rule_matches` honours is covered, because one unguarded column is enough.
for wspec in "lens:*	-	-" "file:-	*	-" "message:-	-	*"; do
  wcol="${wspec%%:*}"; wrow="${wspec#*:}"
  { printf '%s\n' "$BL_HDR"
    printf 'rule\tsuppress\taccepted-risk\t-\t%s\tnoisy\n' "$wrow"; } > "$RB/wild.tsv"
  "$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/wild.tsv" \
    > "$RB/wild.out" 2>/dev/null; rc=$?
  check "wildcard rule on $wcol exits 4, suppresses nothing" \
    "[ $rc -eq 4 ] && [ ! -s '$RB/wild.out' ]"
done
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\taccepted-risk\t-\t**\t*\t?\tnoisy\n'; } > "$RB/wild2.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/wild2.tsv" >/dev/null 2>&1; rc=$?
check "several universal globs together still exit 4" "[ $rc -eq 4 ]"
# Positive control — the guard must reject WILDCARDS, not globbing itself. A
# real glob with a discriminating character has to keep working, or the tests
# above would pass just as well with the rules feature switched off.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\taccepted-risk\t-\t-\tb*\t-\tpolicy: b.py is vendored\n'; } > "$RB/narrow.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/narrow.tsv" \
  --active-only > "$RB/narrow.out" 2>/dev/null; rc=$?
check "positive control: a real glob still suppresses" \
  "[ $rc -eq 1 ] && [ \"\$(wc -l < '$RB/narrow.out')\" -eq 1 ]"
check "positive control: it suppressed only b.py" "grep -q 'shell injection' '$RB/narrow.out'"
# PR #16 round 2 found a rule could look scoped while a `*` was the pattern
# actually applied, because `rule_matches` resolved ALIAS PAIRS (`id or
# rule_id`, `path or file`) and the guard checked the five keys independently.
# The store is now TSV: `lens`, `file` and `message` are one column each, so
# there is no losing alias for a wildcard to hide behind, and the per-column
# wildcard loop above covers every column that can match. Assert the alias
# machinery is really gone rather than assuming it — reintroducing it would
# reopen the hole with nothing watching.
check "no alias pairs remain for a wildcard to hide behind" \
  "! grep -q 'RULE_MATCH_GROUPS\\|resolve_rule_pattern' '$BIN/jjstack-review-baseline'"
check "the three matchable fields are one flat, aliasless list (control)" \
  "grep -q '^RULE_MATCH_KEYS = (\"lens\", \"file\", \"message\")$' '$BIN/jjstack-review-baseline'"


# PR #16 review (P1): `generate` rewrote the store from scratch, so following
# SKILL.md's documented flow for EXTENDING a baseline destroyed every
# human-written rule and previously accepted fingerprint.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\taccepted-risk\t-\tdocs\t-\t-\thuman policy exclusion\n'
  printf 'fingerprint\tsuppress\tbaseline\tsha256:1111111111111111111111111111111111111111111111111111111111111111\tsec\tz.py\tm\taccepted by a human last quarter\n'; } > "$RB/prior.tsv"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "second pass" \
  -o "$RB/prior.tsv" >/dev/null 2>&1; rc=$?
check "generate onto an existing store exits 0" "[ $rc -eq 0 ]"
check "the human-written RULE survives"      "grep -q 'human policy exclusion' '$RB/prior.tsv'"
check "the prior fingerprint survives"       "grep -q 'accepted by a human last quarter' '$RB/prior.tsv'"
check "the new findings are appended"        "[ \"\$(grep -c 'sha256:' '$RB/prior.tsv')\" -eq 3 ]"
# Positive control — merging must be idempotent, not merely additive: a second
# identical run must add nothing, or "3 fingerprints" would grow every run.
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "third pass" \
  -o "$RB/prior.tsv" >/dev/null 2>&1
check "positive control: re-running adds no duplicates" \
  "[ \"\$(grep -c 'sha256:' '$RB/prior.tsv')\" -eq 3 ]"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/prior.tsv" >/dev/null 2>&1; rc=$?
check "positive control: the merged file is still valid to apply" \
  "[ $rc -ne 2 ] && [ $rc -ne 4 ]"
# --replace is the explicit way to start over; nothing else may truncate.
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "fresh" \
  -o "$RB/prior.tsv" --replace >/dev/null 2>&1
check "--replace drops the prior rules on purpose" \
  "! grep -q 'human policy exclusion' '$RB/prior.tsv'"
# A corrupt existing store must stop the run, not be silently overwritten.
printf 'this is not a review store\n' > "$RB/corrupt.tsv"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "x" \
  -o "$RB/corrupt.tsv" >/dev/null 2>&1; rc=$?
check "generate refuses to clobber a corrupt store" "[ $rc -eq 4 ]"
check "the corrupt store is left untouched" "grep -q 'this is not a review store' '$RB/corrupt.tsv'"
check "no .tmp file is left behind" "[ ! -f '$RB/corrupt.tsv.tmp' ]"
# ...but that path returns at LOAD time, before any temp file is created, so
# the check above is vacuous — deleting the unlink cleanup outright kept the
# whole suite green. Reach the write branch instead: `--replace` skips the load,
# a DIRECTORY at the output path lets the .tmp write succeed and only the
# os.replace fail, which is the single branch the cleanup guards.
mkdir -p "$RB/adir"
: > "$RB/adir/keep"
"$BIN/jjstack-review-baseline" generate "$RB/findings.jsonl" --reason "x" \
  -o "$RB/adir" --replace > "$RB/adir.err" 2>&1; rc=$?
check "a failed rename exits 2"                "[ $rc -eq 2 ]"
check "the failed write leaves NO .tmp behind" "[ ! -e '$RB/adir.tmp' ]"
# Positive control — prove the run reached the WRITE branch and not the load
# bail, i.e. that the .tmp really existed a moment earlier. `cannot write` is
# printed only after the .tmp open has already succeeded, and the errno text
# names the .tmp as the rename source.
check "positive control: it failed at the RENAME, not the load" \
  "grep -q 'cannot write' '$RB/adir.err' && grep -q 'adir.tmp' '$RB/adir.err'"
check "positive control: the directory it refused to clobber is intact" \
  "[ -f '$RB/adir/keep' ]"
rm -rf "$RB/adir" "$RB/adir.err"
printf '#jjstack-review-store\tscope=instance\tmax-effect=suppress\tv=1\n' > "$RB/v1.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/v1.tsv" >/dev/null 2>&1; rc=$?
check "unsupported baseline version exits 2" "[ $rc -eq 2 ]"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/gone.tsv" >/dev/null 2>&1; rc=$?
check "missing baseline exits 2" "[ $rc -eq 2 ]"
# A store from a DIFFERENT rung of the ladder is not interchangeable with this
# one. Pointing the suppressing tool at the demoting store must be refused.
printf '#jjstack-review-store\tscope=path-glob\tmax-effect=demote\tv=3\n' > "$RB/wrongscope.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/wrongscope.tsv" >/dev/null 2>&1; rc=$?
check "a store from another rung exits 4" "[ $rc -eq 4 ]"
# The reason-code ceiling is shared data, not a per-tool special case:
# `not-reachable` caps at demote, so it may not appear on a suppression here
# either. Same rule, same file, three tools.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\tnot-reachable\t-\tper*\t-\t-\tdead code\n'; } > "$RB/ceiling.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/ceiling.tsv" >/dev/null 2>&1; rc=$?
check "not-reachable may not suppress here either" "[ $rc -eq 4 ]"

# THE READ PATH IS THE OTHER HALF OF THE LADDER, and it was open. The ceiling
# check asserts a row's effect is WITHIN this scope's maximum; it never asserted
# the row IS a suppression. `demote`, `rank` and `none` all sit BELOW `suppress`,
# so a row spelled that way passed `validate` with `ok` and then suppressed at
# read time anyway, because `apply` acted on any match. That is exactly the
# silent suppression the three stores were kept apart to prevent — and it stayed
# invisible because the ceiling test above writes `effect=suppress`, the one
# spelling the check already rejected. This store has ONE verb; a weaker verdict
# belongs on a wider rung, not in this file.
P0F='{"lens":"security","file":"a.py","start_line":1,"severity":"P0","confidence":0.9,"message":"remote code execution","quote":"eval(x)","explanation":"e","remediation":"r"}'
printf '%s\n' "$P0F" > "$RB/p0.jsonl"
for weak in demote rank none; do
  { printf '%s\n' "$BL_HDR"
    printf 'rule\t%s\tnot-reachable\t-\t-\ta.py\t-\tdead code path\n' "$weak"; } > "$RB/weak.tsv"
  "$BIN/jjstack-review-baseline" validate --baseline "$RB/weak.tsv" >/dev/null 2>&1; rc=$?
  check "a baseline row spelled '$weak' fails validate (exit 4)" "[ $rc -eq 4 ]"
  "$BIN/jjstack-review-baseline" apply "$RB/p0.jsonl" --baseline "$RB/weak.tsv" \
    --active-only >/dev/null 2> "$RB/weak.err"; rc=$?
  check "a baseline row spelled '$weak' cannot suppress a P0 (exit 4)" "[ $rc -eq 4 ]"
  check "no suppression is reported for '$weak'" "! grep -q '1 suppressed' '$RB/weak.err'"
done
# Rules are not the only kind of row — a fingerprint carries an effect column too.
{ printf '%s\n' "$BL_HDR"
  printf 'fingerprint\tdemote\tnot-reachable\tsha256:%064d\t-\ta.py\t-\tdead code path\n' 1; } > "$RB/weakfp.tsv"
"$BIN/jjstack-review-baseline" validate --baseline "$RB/weakfp.tsv" >/dev/null 2>&1; rc=$?
check "a weak-effect FINGERPRINT row is rejected too (exit 4)" "[ $rc -eq 4 ]"
# POSITIVE CONTROL — the byte-identical store spelled `suppress` still validates
# and still suppresses. Without it, "exit 4" above could mean the store shape is
# broken rather than that the effect column is now enforced.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\tbaseline\t-\t-\ta.py\t-\tdead code path\n'; } > "$RB/strong.tsv"
"$BIN/jjstack-review-baseline" validate --baseline "$RB/strong.tsv" >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: the same store spelled 'suppress' validates" "[ $rc -eq 0 ]"
"$BIN/jjstack-review-baseline" apply "$RB/p0.jsonl" --baseline "$RB/strong.tsv" \
  --active-only >/dev/null 2> "$RB/strong.err"; rc=$?
check "POSITIVE CONTROL: and it does suppress the P0" "[ $rc -eq 0 ]"
check "POSITIVE CONTROL: the suppression really was counted" \
  "grep -q '1 suppressed' '$RB/strong.err'"

# Fingerprints fail CLOSED across a jjstack version change: they cannot be
# trusted to still mean what they meant, so they go inert rather than hide.
sed 's/jjstack=.*/jjstack=0.0.0-ancient/' "$RB/bl.tsv" > "$RB/old.tsv"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/old.tsv" \
  --active-only > "$RB/old.out" 2>/dev/null; rc=$?
check "version drift makes fingerprints inert" "[ \"\$(wc -l < '$RB/old.out')\" -eq 2 ]"
check "version drift is a warning, not a hide" "[ $rc -eq 1 ]"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/old.tsv" \
  --active-only --allow-version-drift > "$RB/ovr.out" 2>/dev/null
check "--allow-version-drift re-enables them"  "[ ! -s '$RB/ovr.out' ]"
# Positive control for the drift test — prove the two baselines really do
# differ in version, or "inert" above proves nothing.
check "positive control: drifted baseline has a different version" \
  "! cmp -s '$RB/bl.tsv' '$RB/old.tsv'"
rm -rf "$RB"

echo "== 5h. review skill structural guards =="
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

# Positive controls — a grep that can never fire looks exactly like a clean
# tree. The probe is built from the SHIPPED heading, extracted from the skill
# itself, and the pattern is the SAME shell variable the guard above used. The
# earlier version printed an invented `## Phase 5: one` and grepped it with a
# pattern typed a second time in the test: that pair only ever proved the regex
# matches a string written to match it, and it would keep passing after the
# skill renamed the heading out from under both.
PH5_PAT='^## Phase 5: '
n_phase5=$(grep -c "$PH5_PAT" "$SK" 2>/dev/null)
check "exactly one '## Phase 5: ' heading in the review skill (re-checked via the shared pattern)" \
  "[ \"\$n_phase5\" = 1 ]"
probe_sk="$(mktemp)"
grep "$PH5_PAT" "$SK" > "$probe_sk"
grep "$PH5_PAT" "$SK" >> "$probe_sk"
check "the phase-5 probe was seeded from the shipped heading, not an invented one" \
  "[ -s '$probe_sk' ] && grep -q 'Phase 5' '$probe_sk'"
check "phase-5 guard actually catches a duplicate" \
  "[ \"\$(grep -c \"\$PH5_PAT\" '$probe_sk')\" = 2 ]"
rm -f "$probe_sk"
probe_bin="$(mktemp -d)"
: > "$probe_bin/jjstack-review-blast-radius"; : > "$probe_bin/jjstack-review-blast-radius-census"
check "blast-radius guard actually catches a duplicate" \
  "[ \"\$(ls -1 '$probe_bin' | grep -c '^jjstack-review-blast-radius')\" = 2 ]"
rm -rf "$probe_bin"

# ONE implementation in bin/ is only half of "computed once". The skill also has
# to INVOKE it once. Phase 4.5's consolidation note said blast radius "is computed
# once, in Phase 0", while Module G.1 still told the model to run the scan again
# at the start of Phase 4 into a DIFFERENT path — so a model reading the skill top
# to bottom produced two files with the same basename in two directories, and the
# passes disagreed about which was current. Phase 0's pre-flight is the only
# caller; the skill must name the binary exactly once, in that pre-flight.
n_blast_calls=$(grep -c 'jjstack-review-blast-radius' "$SK" 2>/dev/null)
check "the review skill invokes blast-radius exactly once" "[ \"\$n_blast_calls\" = 1 ]"
check "that one invocation is the Phase 0 pre-flight" \
  "grep -q 'jjstack-review-preflight' '$SK' && ! grep -q 'jjstack-review-blast-radius >' '$SK'"
# Positive control — seeded from the REAL invocation line in the skill, and
# counted with the same pattern the guard uses. Inventing a probe line and
# hardcoding a second copy of the pattern proves only that a regex matches a
# string authored to satisfy it.
BR_PAT='jjstack-review-blast-radius'
n_blast_calls=$(grep -c "$BR_PAT" "$SK" 2>/dev/null)
check "the review skill invokes blast-radius exactly once (re-checked via the shared pattern)" \
  "[ \"\$n_blast_calls\" = 1 ]"
probe_two="$(mktemp)"
grep "$BR_PAT" "$SK" > "$probe_two"
grep "$BR_PAT" "$SK" >> "$probe_two"
check "the blast-radius probe was seeded from the shipped invocation" \
  "[ \"\$(grep -c . '$probe_two')\" = 2 ] && grep -q -- 'jjstack-review-blast-radius' '$probe_two'"
check "the single-invocation guard actually catches a second run" \
  "[ \"\$(grep -c \"\$BR_PAT\" '$probe_two')\" = 2 ]"
rm -f "$probe_two"
# The widening flag has to REACH the scan, not merely appear in the file.
# `grep -q -- '--also-repo' preflight` matched the header, the usage line and
# the arg-parsing branch, so deleting the actual `"${ALSO[@]+...}"` forwarding
# from the `run_pass blast` line left the assertion green — an inert guard on
# the one route Module G.1 leaves for widening the scan. Drive it end to end
# instead: a caller that lives ONLY in the sibling repo must appear in the
# blast-radius report the pre-flight produced.
ALSO_T="$(mktemp -d)"
mkdir -p "$ALSO_T/repo/src" "$ALSO_T/sib"
git -C "$ALSO_T/repo" init -q
printf 'def build_token(user, ttl):\n    return "t"\n' > "$ALSO_T/repo/src/auth.py"
git -C "$ALSO_T/repo" add -A >/dev/null 2>&1
git -C "$ALSO_T/repo" -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
printf 'def build_token(user, ttl, scope):\n    return "t"\n' > "$ALSO_T/repo/src/auth.py"
printf 'from auth import build_token\nhandler = build_token("u", 60, "read")\n' > "$ALSO_T/repo/src/api.py"
printf 'from auth import build_token\n' > "$ALSO_T/sib/consumer.py"
"$BIN/jjstack-review-preflight" --out "$ALSO_T/out" --repo "$ALSO_T/repo" \
  --base HEAD --also-repo "$ALSO_T/sib" --skip-tests > "$ALSO_T/pf.log" 2>&1
check "pre-flight forwards --also-repo to the one blast-radius run" \
  "grep -q '(sib) consumer.py' '$ALSO_T/out/blast-radius.md'"
# POSITIVE CONTROL for the flag, not for the scanner: the same pre-flight
# WITHOUT --also-repo must not find the sibling caller, or the check above would
# pass on a scan that always reads everything.
"$BIN/jjstack-review-preflight" --out "$ALSO_T/out2" --repo "$ALSO_T/repo" \
  --base HEAD --skip-tests > "$ALSO_T/pf2.log" 2>&1
check "the sibling caller is absent when --also-repo is not passed (control)" \
  "! grep -q 'consumer.py' '$ALSO_T/out2/blast-radius.md'"
check "the in-repo caller is found either way (control)" \
  "grep -q 'src/api.py' '$ALSO_T/out2/blast-radius.md'"
rm -rf "$ALSO_T"

# The stale-API phase's own marketing filter must not leak around its output:
# references/vendor-lessons-macroscope.md calls the 55% figure "a vendor-adjacent
# number", and the skill and the script both stated it as fact.
n_bare55=$(grep -cE 'cut third-party-library review comments (by )?55%' "$SK" "$BIN/jjstack-review-dep-inventory" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
check "the 55% figure is never asserted as bare fact" "[ \"\$n_bare55\" = 0 ]"
check "the 55% figure is attributed where it is used" \
  "grep -q 'vendor-adjacent' '$SK' && grep -q 'vendor-adjacent' '$BIN/jjstack-review-dep-inventory'"
# The per-finding WebSearch had no bound and no per-library dedup, in a skill
# whose other expensive pass caps itself in three places.
check "the stale-API lookup carries an explicit bound" \
  "grep -q 'Cap the phase at 10 lookups' '$SK'"
check "the stale-API lookup dedups per library+version" \
  "grep -q 'One lookup per (library, version)' '$SK'"
# Exit 4 is a new, opposite-meaning state; the skill must not leave the model
# reading a parse failure as the safe "no dependencies" case.
check "the skill distinguishes dep-inventory exit 3 from exit 4" \
  "grep -q 'Exit 4 (manifests found, nothing parsed)' '$SK'"

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
# So: the corpus is every file that can carry a routing instruction, the test is
# the bare word (a rephrasing cannot dodge it — this guard is meant to fail
# closed, and if that section is ever wanted, 5f must define it first), and the
# positive control below is built from the literal strings this tree really
# contained, recovered from git, not from anything invented here.
#
# ROUND 2: "every file that can carry a routing instruction" was still an
# ENUMERATED list — SKILL.md, the changelog, references/ and the review tools —
# and the comment above it claimed the general thing. README.md, TUTORIAL.md,
# hooks/, bin/jjstack-capture-* and 49 other skills/*/SKILL.md were all outside
# it, several of them review-adjacent, so a real shipped routing pasted into any
# of them left the guard green. An allow-list that has to be edited whenever a
# file is added is a guard that decays by default. The corpus is now DERIVED:
# every text file git tracks, minus this test tree, which holds the probes.
route_corpus() {   # $1 = repo root -> every shipped text file, NUL-free list
  git -C "$1" ls-files -z -- . ':!:test/*' 2>/dev/null | tr '\0' '\n'
}
mapfile -t ROUTE_CORPUS < <(route_corpus "$DIR")
# One newline-joined copy, queried with a here-string rather than a pipe. Over a
# 147-file corpus `printf ... | grep -q` is a coin flip: -q exits on the first
# match, printf takes SIGPIPE, and `set -o pipefail` reports the whole check as
# failed. Two runs of this suite went red on a file that was plainly in the list.
ROUTE_CORPUS_TXT="$(printf '%s\n' "${ROUTE_CORPUS[@]}")"
# An unexpanded glob or a moved file is how a widened corpus silently narrows
# again: grep cannot read the path, says nothing, and reports a clean tree.
route_missing=0
for f in "${ROUTE_CORPUS[@]}"; do [ -f "$DIR/$f" ] || route_missing=$((route_missing + 1)); done
check "positive control: every file in the routing corpus exists" "[ $route_missing -eq 0 ]"
check "positive control: the corpus reaches past SKILL.md into references/" \
  "[ \"\$(grep -c '^references/' <<< \"\$ROUTE_CORPUS_TXT\")\" -ge 3 ]"
check "positive control: the corpus includes the changelog" \
  "grep -qx 'CHANGELOG\.md' <<< \"\$ROUTE_CORPUS_TXT\""
check "positive control: the corpus includes the ledger tool" \
  "grep -qx 'bin/jjstack-review-ledger' <<< \"\$ROUTE_CORPUS_TXT\""
# The four files round 2 named as blind spots, plus the long tail of sibling
# skills. Naming them is not the guard — the derivation is — but if the
# derivation ever narrows back to an allow-list these go red first.
for f in README.md TUTORIAL.md hooks/shared-memory.sh bin/jjstack-capture-review-refs; do
  check "positive control: the corpus reaches $f" \
    "grep -qx '$f' <<< \"\$ROUTE_CORPUS_TXT\""
done
check "positive control: the corpus reaches every sibling skill, not just review" \
  "[ \"\$(grep -c '^skills/.*/SKILL\.md$' <<< \"\$ROUTE_CORPUS_TXT\")\" -ge 40 ]"
check "positive control: the corpus is derived, not enumerated (100+ files)" \
  "[ \"\${#ROUTE_CORPUS[@]}\" -ge 100 ]"

# No -c: over several files `grep -c` prints one count PER FILE, so piping that
# to `wc -l` would count files and report a constant. Count matching lines.
# -I so a binary blob in the derived corpus cannot turn a count into a
# "Binary file matches" line, and xargs so a repo-sized corpus cannot blow ARG_MAX.
route_hits() {     # $1 = repo root -> matching LINES across the whole corpus
  route_corpus "$1" | grep -v '^$' \
    | ( cd "$1" && xargs -d '\n' -r grep -inIE 'appendix' 2>/dev/null ) | wc -l | tr -d ' '
}
n_appendix=$(route_hits "$DIR")
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

# THE STRONGEST CONTROL — round 2's actual reproduction. Pasting a real shipped
# routing literal into README.md left the guard green, because README.md was
# outside the enumerated corpus. This runs the guard's OWN derivation and its
# OWN count over a throwaway repo shaped like this one, with the same literal in
# each file the old corpus could not see. Narrow the derivation back to a list
# and this goes red before anything ships.
route_probe="$(mktemp -d)"
mkdir -p "$route_probe"/{hooks,bin,skills/other,test}
git -C "$route_probe" init -q 2>/dev/null
for f in README.md TUTORIAL.md hooks/shared-memory.sh bin/jjstack-capture-review-refs \
         skills/other/SKILL.md test/smoke.sh; do
  head -1 "$probe_sec" > "$route_probe/$f"
done
git -C "$route_probe" add -A >/dev/null 2>&1
check "the guard sees a shipped routing in every file the old corpus missed" \
  "[ \"\$(route_hits '$route_probe')\" = 5 ]"
check "the guard still skips the test tree that holds its own probes" \
  "[ \"\$(route_corpus '$route_probe' | grep -c '^test/')\" = 0 ]"
rm -rf "$route_probe"
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

echo "== 7b2. --mark must snapshot every git file state, not just the ones with a fixture =="
# Round 1 taught --mark to exclude the user's pre-existing TRACKED edits, because
# the fixture used tracked files. `git stash create` captures the index and the
# tracked worktree and ignores untracked files BY DESIGN, so a file the user
# wrote BEFORE the review still surfaced under "new untracked files" while the
# header affirmed "marker taken before the fixing step" — post-pass 2 then files
# the user's own scratch file back at them as a P1. The old fixture could not see
# it: it removed XDG_CACHE_HOME (destroying the marker) before creating its
# untracked file, so it only ever exercised the already-handled HEAD fallback.
#
# This fixture enumerates every state git distinguishes, all of it created BEFORE
# the marker, and asserts the marker excludes each one.
MKS="$(mktemp -d)"; MKR="$MKS/repo"; mkdir -p "$MKR"
XDG_CACHE_HOME="$MKS/cache"; export XDG_CACHE_HOME
git -C "$MKR" init -q >/dev/null 2>&1
git -C "$MKR" config user.email t@example.com >/dev/null 2>&1
git -C "$MKR" config user.name  jjstack-test   >/dev/null 2>&1
printf 'ignored.log\n' > "$MKR/.gitignore"
for f in clean mod staged del ren fix; do printf 'base\n' > "$MKR/$f.txt"; done
git -C "$MKR" add -A >/dev/null 2>&1
git -C "$MKR" commit -qm init >/dev/null 2>&1
# --- the user's own work: every state git distinguishes, all before the marker
printf 'PRE_MODIFIED\n' >> "$MKR/mod.txt"                    # tracked-modified
printf 'PRE_STAGED\n'   >> "$MKR/staged.txt"                 # staged
git -C "$MKR" add staged.txt >/dev/null 2>&1
rm -f "$MKR/del.txt"                                         # deleted
mv "$MKR/ren.txt" "$MKR/renamed.txt"                         # renamed = delete + untracked
printf 'PRE_UNTRACKED\n' > "$MKR/pre_untouched.txt"          # untracked, never touched again
printf 'PRE_EDITED\n'    > "$MKR/pre_edited.txt"             # untracked, later edited by the review
printf 'PRE_DOOMED\n'    > "$MKR/pre_doomed.txt"             # untracked, later deleted by the review
printf 'PRE_IGNORED\n'   > "$MKR/ignored.log"                # ignored
"$BIN/jjstack-review-autofix-diff" --repo "$MKR" --mark >/dev/null 2>&1
# --- only now does the "review" apply its auto-fixes ---
printf 'AUTOFIX_TRACKED\n'  >> "$MKR/fix.txt"
printf 'AUTOFIX_NEW\n'       > "$MKR/autofix_new.txt"
printf 'AUTOFIX_APPENDED\n' >> "$MKR/pre_edited.txt"
rm -f "$MKR/pre_doomed.txt"
mout="$("$BIN/jjstack-review-autofix-diff" --repo "$MKR" 2>&1)"; mrc=$?
# Positive control first: if detection were simply broken, every exclusion below
# would pass for the wrong reason.
check "mark/states: the review's tracked edit is reported" \
  "[ $mrc -eq 0 ] && grep -q 'AUTOFIX_TRACKED' <<<\"\$mout\""
check "mark/states: the review's new untracked file is reported" \
  "grep -q 'autofix_new.txt' <<<\"\$mout\""
# One assertion per pre-marker state. Each is the USER's work, not the review's.
check "mark/states: tracked-clean never appears"                "! grep -q 'clean.txt' <<<\"\$mout\""
check "mark/states: tracked-modified is excluded"               "! grep -q 'PRE_MODIFIED' <<<\"\$mout\""
check "mark/states: staged is excluded"                         "! grep -q 'PRE_STAGED' <<<\"\$mout\""
check "mark/states: a deletion is excluded"                     "! grep -q 'del.txt' <<<\"\$mout\""
check "mark/states: an ignored file is excluded"                "! grep -q 'ignored.log' <<<\"\$mout\""
check "mark/states: pre-existing UNTRACKED is excluded"         "! grep -q 'pre_untouched.txt' <<<\"\$mout\""
check "mark/states: the untracked half of a rename is excluded" "! grep -q 'renamed.txt' <<<\"\$mout\""
# ...but the subtraction must not overshoot: an untracked file that already
# existed and which the review then CHANGED is the review's work and must still
# surface — and be distinguishable from a file the review created.
check "mark/states: an edited pre-existing untracked file still surfaces" \
  "grep -q 'pre_edited.txt' <<<\"\$mout\""
check "mark/states: it is reported as changed, not as new" \
  "grep -q 'existed at the marker and changed' <<<\"\$mout\""
check "mark/states: an untracked file the review deleted is reported" \
  "grep -q 'pre_doomed.txt' <<<\"\$mout\""
# And the pass must not claim the review did something when it did nothing: a
# tree whose only dirt predates the marker is "no auto-fixes" — exit 4.
MK2="$MKS/repo2"; mkdir -p "$MK2"
git -C "$MK2" init -q >/dev/null 2>&1
git -C "$MK2" config user.email t@example.com >/dev/null 2>&1
git -C "$MK2" config user.name  jjstack-test   >/dev/null 2>&1
printf 'base\n' > "$MK2/a.txt"
git -C "$MK2" add -A >/dev/null 2>&1
git -C "$MK2" commit -qm init >/dev/null 2>&1
printf 'user scratch\n' > "$MK2/user_only.txt"
"$BIN/jjstack-review-autofix-diff" --repo "$MK2" --mark >/dev/null 2>&1
"$BIN/jjstack-review-autofix-diff" --repo "$MK2" >/dev/null 2>&1; rc=$?
check "mark/states: pre-existing dirt alone is 'no auto-fixes' (exit 4)" "[ $rc -eq 4 ]"
unset XDG_CACHE_HOME
rm -rf "$MKS"

echo "== 7c. review-calibration (pattern-class scope — may only RANK) =="
# Post-pass 5: a class the team keeps rejecting must be ranked DOWN THE PAGE and a
# class they keep confirming ranked up, or the reviewer re-guesses every run.
# Nothing leaves the report and no confidence ever moves — this is ordering only.
# The value is entirely in the key normalization (same class -> same row) and the
# clamped, placement-only rank arithmetic.
# This is the WIDEST rung of the memory ladder: its key is a global pattern
# class, so its ceiling is `rank` — placement only, never a demotion and never a
# suppression.
CAL="$(mktemp -d)"; CSTORE="$CAL/calibration.tsv"
"$BIN/jjstack-review-calibration" report --store "$CSTORE" >/dev/null 2>&1; rc=$?
check "no store yet exits 4 (skip, no adjustment)" "[ $rc -eq 4 ]"
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "Unused Import!!" --verdict rejected --code style-only >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "unused-import" --verdict rejected --code style-only >/dev/null 2>&1
out=$("$BIN/jjstack-review-calibration" suggest --store "$CSTORE" --key "UNUSED import" 2>&1)
check "keys normalize to one row across spellings" "printf '%s' \"\$out\" | grep -q 'rejected=2'"
check "two rejections rank the pattern at -20"     "grep -q 'rank=-20' <<<\"\$out\""
check "a negative rank demotes rather than rescores" "grep -q 'placement=demoted' <<<\"\$out\""
# The whole point of the rewrite: calibration must never emit an instruction to
# change a finding's confidence. The score is a claim about the code; the
# demotion is a claim about the team's prior decision.
check "suggest never emits a confidence delta"     "! grep -qi 'delta=' <<<\"\$out\""
# ...and it must state its EFFECT on every line, so nothing downstream can read
# a negative rank as something stronger than placement.
check "suggest states effect=rank even when demoting" "grep -q 'effect=rank' <<<\"\$out\""
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "unused-import" --verdict rejected --code style-only >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "unused-import" --verdict rejected --code style-only >/dev/null 2>&1
out=$("$BIN/jjstack-review-calibration" suggest --store "$CSTORE" --key "unused-import" 2>&1)
check "rank is floored at -30" "grep -q 'rank=-30' <<<\"\$out\""
for _ in 1 2 3; do
  "$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "missing-migration" --verdict accepted >/dev/null 2>&1
done
out=$("$BIN/jjstack-review-calibration" suggest --store "$CSTORE" --key "missing migration" 2>&1)
check "rank is capped at +20" "grep -q 'rank=20' <<<\"\$out\""
# A confirmed pattern ranks up but must NOT be demoted, and must still not carry
# a score instruction — promotion is placement too.
check "a positive rank keeps normal placement" "grep -q 'placement=normal' <<<\"\$out\""
out=$("$BIN/jjstack-review-calibration" suggest --store "$CSTORE" --key "never-seen" 2>&1); rc=$?
check "unknown key exits 4 with no adjustment" "[ $rc -eq 4 ]"
check "unknown key reports rank=0"             "grep -q 'rank=0' <<<\"\$out\""
# Positive control — verdict validation that never rejects anything would let a
# typo ("acccepted") silently become an uncounted row, and the store would rot
# while every read still looked healthy.
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key k --verdict acccepted >/dev/null 2>&1; rc=$?
check "invalid verdict actually rejected (exit 2)" "[ $rc -eq 2 ]"
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --verdict accepted >/dev/null 2>&1; rc=$?
check "missing --key is a usage error (2)" "[ $rc -eq 2 ]"
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "tabby" --verdict accepted --note "a	b	c" >/dev/null 2>&1
# Field-count integrity: a tab in free text would shift every column after it.
# The old form, `awk -F'\t' '/tabby/{exit !(NF==8)}'`, exits 0 when NO line
# matches — so it passed just as happily when the row was missing entirely.
# Assert the row EXISTS and is well formed, and prove the assertion can fail.
row_is_intact() { # row_is_intact <store> <key>
  awk -F'\t' -v k="$2" '$2 == k { seen = 1; if (NF != 8) bad = 1 }
                        END { exit (seen && !bad) ? 0 : 1 }' "$1"
}
check "tabs in --note cannot corrupt the row" "row_is_intact '$CSTORE' tabby"
check "control: the row check fails when the row is absent" \
  "! row_is_intact '$CSTORE' definitely-never-recorded"
before=$(wc -l < "$CSTORE")
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key "dry" --verdict accepted --dry-run >/dev/null 2>&1
check "--dry-run appends nothing" "[ \$(wc -l < '$CSTORE') -eq $before ]"
# Ordering IS the product of `report` — it is the ranked view of the ledger.
# `%+6d` emits "+20", and `sort -n` cannot parse a leading '+', so the sort key
# collapsed to 0 and the ranked output came back unranked. The keys below are
# chosen so alphabetical order is NOT rank order; otherwise a broken sort could
# come out right by coincidence.
ORD="$CAL/ordering.tsv"
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "aaa-top" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "aaa-top" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "bbb-mid" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "ccc-low" --verdict rejected --code style-only >/dev/null 2>&1
rout="$("$BIN/jjstack-review-calibration" report --store "$ORD" 2>&1)"
# The rank column of each data row, in the order printed (last field is the
# placement word, so the rank is the one before it).
ranks="$(printf '%s\n' "$rout" | awk '/(demoted|normal)$/ { print $(NF-1)+0 }')"
check "report emits one row per pattern key" \
  "[ \$(printf '%s\n' \"\$ranks\" | grep -c .) -eq 3 ]"
check "report actually orders by rank" \
  "[ \"\$ranks\" = \"\$(printf '%s\n' \"\$ranks\" | sort -n)\" ]"
check "report puts the most-demoted pattern first" \
  "[ \"\$(printf '%s\n' \"\$ranks\" | head -1)\" = '-10' ]"
check "report puts the highest-ranked pattern last" \
  "[ \"\$(printf '%s\n' \"\$ranks\" | tail -1)\" = '20' ]"
# Ties must not be left to awk's hash order, or the ranked view reshuffles
# between two runs over an unchanged ledger.
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "tie-a" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "tie-b" --verdict accepted >/dev/null 2>&1
r1="$("$BIN/jjstack-review-calibration" report --store "$ORD" 2>&1)"
r2="$("$BIN/jjstack-review-calibration" report --store "$ORD" 2>&1)"
check "report is byte-identical across runs on an unchanged ledger" "[ \"\$r1\" = \"\$r2\" ]"
check "tied ranks fall back to key order" \
  "[ \"\$(printf '%s\n' \"\$r1\" | awk '/(demoted|normal)\$/ && \$1 ~ /^tie-/ { print \$1 }' | tr '\n' ' ')\" = 'tie-a tie-b ' ]"
# A rejection is a decision, and a decision is explained — with a code from the
# ONE shared vocabulary, never a fourth private list.
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key noreason --verdict rejected >/dev/null 2>&1; rc=$?
check "a rejection without a reason code exits 2" "[ $rc -eq 2 ]"
"$BIN/jjstack-review-calibration" record --store "$CSTORE" --key bogus --verdict rejected --code feels-fine >/dev/null 2>&1; rc=$?
check "an invented reason code exits 2" "[ $rc -eq 2 ]"
check "the store declares its scope and ceiling" \
  "head -n 1 '$CSTORE' | grep -q 'scope=pattern-class.*max-effect=rank'"

# POSITIVE CONTROL — the ladder cap can actually fire. A hand-edited row that
# claims `suppress` from the widest key is precisely the failure the three
# stores were kept apart to prevent, so it must be rejected by arithmetic, not
# by anyone remembering the rule.
printf '2026-01-01\tevil\trejected\tsuppress\tstyle-only\t-\t-\t-\n' >> "$CSTORE"
"$BIN/jjstack-review-calibration" validate --store "$CSTORE" > /dev/null 2> "$CAL/ladder.err"; rc=$?
check "POSITIVE CONTROL: a calibration row may not suppress (exit 4)" "[ $rc -eq 4 ]"
check "the ladder error names the ceiling" "grep -q \"may emit at most 'rank'\" '$CAL/ladder.err'"
"$BIN/jjstack-review-calibration" report --store "$CSTORE" >/dev/null 2>&1; rc=$?
check "a ladder-violating store is not silently read" "[ $rc -eq 4 ]"
# ...and the same file WITHOUT the violating row validates clean, or "exit 4"
# above would prove only that validate is broken.
grep -v '	evil	' "$CSTORE" > "$CAL/clean.tsv"
"$BIN/jjstack-review-calibration" validate --store "$CAL/clean.tsv" >/dev/null 2>&1; rc=$?
check "the same store without that row validates clean" "[ $rc -eq 0 ]"

# A store from a DIFFERENT rung is not interchangeable with this one.
printf '#jjstack-review-store\tscope=instance\tmax-effect=suppress\tv=3\n' > "$CAL/wrong.tsv"
"$BIN/jjstack-review-calibration" validate --store "$CAL/wrong.tsv" >/dev/null 2>&1; rc=$?
check "a store from another rung exits 4" "[ $rc -eq 4 ]"

# ...and refusing it on the READ path is only half the guarantee. `record` used
# to validate nothing, so it appended a calibration row straight into another
# rung's file: the write succeeded with exit 0 and every subsequent operation on
# the victim store then failed with exit 4 until a human hand-edited it. Three
# stores that refuse each other on two of three write paths are not a ladder.
XL="$CAL/foreign-ledger.tsv"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
  --code prior-decision --note n --ledger "$XL" >/dev/null 2>&1
before=$(wc -l < "$XL")
"$BIN/jjstack-review-calibration" record --store "$XL" --key "some pattern" --verdict accepted >/dev/null 2>&1; rc=$?
check "record into another rung's store exits 4" "[ $rc -eq 4 ]"
check "record into another rung's store appends nothing" "[ \$(wc -l < '$XL') -eq $before ]"
"$BIN/jjstack-review-ledger" --validate --ledger "$XL" >/dev/null 2>&1; rc=$?
check "the foreign store is left valid on its own tool" "[ $rc -eq 0 ]"
# A store of the RIGHT scope that already holds a bad row must stop a write too:
# appending a decision to a file no reader will accept just buries the decision.
BADC="$CAL/corrupt.tsv"
printf '#jjstack-review-store\tscope=pattern-class\tmax-effect=rank\tv=1\n' > "$BADC"
printf '2020-01-01\tk\tmaybe\trank\t-\t-\t-\tbogus verdict\n' >> "$BADC"
before=$(wc -l < "$BADC")
"$BIN/jjstack-review-calibration" record --store "$BADC" --key k2 --verdict accepted >/dev/null 2>&1; rc=$?
check "record into a corrupt own-scope store exits 4" "[ $rc -eq 4 ]"
check "record into a corrupt own-scope store appends nothing" "[ \$(wc -l < '$BADC') -eq $before ]"
# POSITIVE CONTROL — a healthy store of this scope still accepts a write, or the
# two "exit 4" results above would only prove that record is broken for everything.
GOODC="$CAL/healthy.tsv"
"$BIN/jjstack-review-calibration" record --store "$GOODC" --key k3 --verdict accepted >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: a healthy store still accepts a record (exit 0)" "[ $rc -eq 0 ]"
check "POSITIVE CONTROL: and the recorded row really landed" \
  "awk -F'\t' '\$2==\"k3\" && \$3==\"accepted\"{f=1} END{exit !f}' '$GOODC'"
# A plain `while read` drops a final line with no trailing newline, so the
# ladder-violating LAST row of a store validated `ok` while grep and awk saw it.
CN="$CAL/nonewline.tsv"
printf '#jjstack-review-store\tscope=pattern-class\tmax-effect=rank\tv=1\n' > "$CN"
printf '2026-01-01\tevil\trejected\tsuppress\tstyle-only\t-\t-\t-' >> "$CN"
"$BIN/jjstack-review-calibration" validate --store "$CN" >/dev/null 2>&1; rc=$?
check "a violating LAST row with no trailing newline still exits 4" "[ $rc -eq 4 ]"
check "POSITIVE CONTROL: that row really lacks a trailing newline" \
  "[ -n \"\$(tail -c 1 '$CN')\" ]"
rm -rf "$CAL"
echo "== 7d. review-run-report (per-run audit trail, NOT memory) =="
# /review casts wide on purpose, so the interesting question is not what it
# reports but what it decided NOT to report. This script is the accountability
# layer: every finding gets a disposition and a reason code, three invariants
# are machine-enforced, and dedup/exposure/corroboration are computed rather
# than guessed. Guards that can't fire are worthless, so each invariant below
# has a POSITIVE CONTROL feeding it input that must be rejected.
TRI="$(mktemp -d)"
# One findings row: 7 fields joined by real tabs. Hand-writing the tabs into a
# format string is how the first draft of these tests silently produced
# 6-column rows, so the join lives in one place.
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

# A well-formed findings file: two lenses on the same defect (must collapse), one
# demoted-by-prior-decision item, one baseline-suppressed nit, one deferred
# vendor finding. Dispositions track the enrich-only model — no score bands.
{
  row P1 80 src/auth.py:42      security    report   -              'missing authz check on admin route'
  row P1 72 src/auth.py:42      correctness report   -              'Missing authz check on admin route!'
  row P2 55 src/util.py:9       perf        demoted  prior-decision 'N+1 query in loop'
  row P3 30 tests/test_x.py:5   style       suppress baseline       'trailing whitespace'
  row P2 40 vendor/lib/x.js:100 security    defer    not-reachable  'unused eval path'
} > "$TRI/good.tsv"

"$BIN/jjstack-review-run-report" "$TRI/good.tsv" --out "$TRI/good.md" > "$TRI/good.out" 2> "$TRI/good.err"
rc=$?
check "review-run-report exits 0 on valid findings" "[ $rc -eq 0 ]"
check "renders a run report to --out"           "[ -f '$TRI/good.md' ]"
check "dedups two lenses on one defect"         "grep -q 'unique=4 collapsed=1' '$TRI/good.out'"
# The lens list is SORTED, not in arrival order. This assertion used to pin
# `security, correctness` — the order the two rows happen to sit in the fixture
# — which meant the rendered page was a function of row order. Both lenses must
# still be named; they are now named in a fixed order, and the check below
# proves reversing the rows does not change the rendering.
check "counts corroborating lenses"             "grep -q 'correctness, security' '$TRI/good.md'"
check "both corroborating lenses are still named" \
      "grep -q 'src/auth.py:42' '$TRI/good.md' && grep -q 'correctness' '$TRI/good.md' && grep -q 'security' '$TRI/good.md'"
tac "$TRI/good.tsv" > "$TRI/good.rev.tsv"
"$BIN/jjstack-review-run-report" "$TRI/good.rev.tsv" --out "$TRI/good.rev.md" > /dev/null 2>&1
check "the lens list does not depend on which row came first" \
      "grep -q 'correctness, security' '$TRI/good.rev.md'"
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
"$BIN/jjstack-review-run-report" "$TRI/silent.tsv" --out "$TRI/silent.md" > /dev/null 2> "$TRI/silent.err"
rc=$?
check "POSITIVE CONTROL: silent drop rejected (exit 4)" "[ $rc -eq 4 ]"
check "silent drop names the invariant"                 "grep -q 'never dropped silently' '$TRI/silent.err'"
check "invalid findings render nothing"                 "[ ! -f '$TRI/silent.md' ]"

# POSITIVE CONTROL 2 — reachability may deprioritise, never delete.
row P2 30 src/b.py:1 sec suppress not-reachable 'deleted via reachability' > "$TRI/reach.tsv"
"$BIN/jjstack-review-run-report" "$TRI/reach.tsv" > /dev/null 2> "$TRI/reach.err"
rc=$?
check "POSITIVE CONTROL: not-reachable cannot suppress (exit 4)" "[ $rc -eq 4 ]"
check "not-reachable error offers defer/demoted instead"         "grep -q 'deprioritise' '$TRI/reach.err'"

# POSITIVE CONTROL 3 — a P0/P1 may be deferred, never made to disappear.
row P0 90 src/c.py:1 sec suppress style-only 'top severity vanished' > "$TRI/p0.tsv"
"$BIN/jjstack-review-run-report" "$TRI/p0.tsv" > /dev/null 2> "$TRI/p0.err"
rc=$?
check "POSITIVE CONTROL: P0 cannot be suppressed (exit 4)" "[ $rc -eq 4 ]"
check "P0 error names the severity"                        "grep -q 'P0 may not be suppressed' '$TRI/p0.err'"

# Vocabulary is closed — an invented reason code is a failure, not a passthrough.
row P2 30 src/d.py:1 sec defer feels-fine 'invented reason code' > "$TRI/vocab.tsv"
"$BIN/jjstack-review-run-report" "$TRI/vocab.tsv" > /dev/null 2> "$TRI/vocab.err"
rc=$?
check "POSITIVE CONTROL: unknown reason code rejected" "[ $rc -eq 4 ]"

# Reporting a finding in code nobody here authored is advisory noise, not fatal.
row P2 70 node_modules/x/y.js:3 sec report - 'vendor finding reported' > "$TRI/adv.tsv"
"$BIN/jjstack-review-run-report" "$TRI/adv.tsv" > /dev/null 2> "$TRI/adv.err"
rc=$?
check "vendor-path report warns but still exits 0" "[ $rc -eq 0 ]"
check "vendor-path report emits an ADVISORY"       "grep -q 'ADVISORY' '$TRI/adv.err'"

# Phase 4.5b is ORDERED to "drop the finding and record it as a stale-knowledge
# false positive" when current docs disprove it — and the closed vocabulary had
# nowhere to record that. `out-of-scope` is defined as "never raised", which is
# false for a finding that WAS raised and then disproved, and `suppress` is
# forbidden for a P0/P1 by invariant 3. So the one phase permitted to delete had
# no accounting: the finding just left. `refuted` + `stale-api` is that row.
row P1 85 src/e.py:1 stale-api refuted stale-api 'API changed in 2.0; code is correct per current docs (https://example/docs)' > "$TRI/ref.tsv"
"$BIN/jjstack-review-run-report" "$TRI/ref.tsv" --out "$TRI/ref.md" > "$TRI/ref.out" 2> "$TRI/ref.err"
rc=$?
check "a refuted stale-API finding is a legal ledger row" "[ $rc -eq 0 ]"
check "a refuted P1 is accepted (invariant 3 is about suppress)" "[ -f '$TRI/ref.md' ]"
check "the refuted finding stays visible with its evidence" \
      "grep -q 'current docs' '$TRI/ref.md'"
check "refuted gets its own rendered section" "grep -q 'Refuted' '$TRI/ref.md'"
check "refuted is counted in the tally"       "grep -q 'refuted=1' '$TRI/ref.out'"
# POSITIVE CONTROL 4a — `refuted` may not carry any other reason, or it becomes
# a general delete hatch for anything a reviewer dislikes.
row P2 30 src/f.py:1 sec refuted style-only 'refuted for the wrong reason' > "$TRI/ref2.tsv"
"$BIN/jjstack-review-run-report" "$TRI/ref2.tsv" > /dev/null 2> "$TRI/ref2.err"
rc=$?
check "POSITIVE CONTROL: refuted with a non-stale-api reason rejected" "[ $rc -eq 4 ]"
check "the pairing error names both halves" "grep -q 'only legal together' '$TRI/ref2.err'"
# POSITIVE CONTROL 4b — and `stale-api` may not ride any other disposition, or a
# P0/P1 could be routed past invariant 3 by relabelling it.
row P0 90 src/g.py:1 sec suppress stale-api 'P0 suppressed via stale-api' > "$TRI/ref3.tsv"
"$BIN/jjstack-review-run-report" "$TRI/ref3.tsv" > /dev/null 2> "$TRI/ref3.err"
rc=$?
check "POSITIVE CONTROL: stale-api cannot ride suppress" "[ $rc -eq 4 ]"

# A missing findings file is a clean exit 3, not a crash or a silent success.
"$BIN/jjstack-review-run-report" "$TRI/nope.tsv" > /dev/null 2>&1
rc=$?
check "missing findings file exits 3" "[ $rc -eq 3 ]"

# The rename is not cosmetic. This tool was mistaken for one of the three review
# MEMORY stores by four separate PRs, so it now refuses one structurally: every
# memory store opens with a #jjstack-review-store header, and a run report is
# never rendered from one.
printf '#jjstack-review-store\tscope=path-glob\tmax-effect=demote\tv=1\n' > "$TRI/store.tsv"
"$BIN/jjstack-review-run-report" "$TRI/store.tsv" > /dev/null 2> "$TRI/store.err"
rc=$?
check "POSITIVE CONTROL: a memory store is refused (exit 2)" "[ $rc -eq 2 ]"
check "the refusal says it is not memory" "grep -q 'MEMORY store' '$TRI/store.err'"
# ...and the same file without that one header line renders fine, or the refusal
# above would prove only that the tool is broken.
row P2 30 src/e2.py:1 sec report - 'ordinary finding' > "$TRI/nostore.tsv"
"$BIN/jjstack-review-run-report" "$TRI/nostore.tsv" > /dev/null 2>&1; rc=$?
check "the same findings without that header render" "[ $rc -eq 0 ]"

# --dry-run validates without writing — the house flag on every bin/ script.
"$BIN/jjstack-review-run-report" "$TRI/good.tsv" --out "$TRI/dry.md" --dry-run >/dev/null 2>&1
check "--dry-run writes nothing" "[ ! -f '$TRI/dry.md' ]"

# The reason-code ceiling is DATA now (bin/jjstack-review-vocab.tsv), shared with
# all three memory stores. Deleting the not-reachable row from the vocabulary
# would break this, which is the point: one definition, four consumers.
check "the shared vocabulary is the only reason-code list" \
  "grep -q '^reason	not-reachable	demote' '$BIN/jjstack-review-vocab.tsv'"
check "the run report defines no reason codes of its own" \
  "! grep -q 'unverified prior-decision low-confidence' '$BIN/jjstack-review-run-report'"

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
"$BIN/jjstack-review-run-report" "$TRI/absorb.tsv" --out "$TRI/absorb.md" > "$TRI/absorb.out" 2>&1
rc=$?
check "merged group is not suppressed (exit 0)"    "[ $rc -eq 0 ]"
check "merge keeps the HIGHEST severity"           "grep -q '| P0 | 95 |' '$TRI/absorb.md'"
check "merge keeps the WEAKEST disposition"        "grep -q 'report=1 unconfirmed=0 demoted=0 defer=0 suppress=0' '$TRI/absorb.out'"
check "absorbed P0 lands in the reported section"  "grep -q 'allowing auth bypass' '$TRI/absorb.md'"
# The claim of the ABSORBED row is not deleted either — it rides along on the
# merged row (see the equal-severity regression below). What must be empty is
# the SUPPRESSED SECTION, so that is what this checks; the old spelling greped
# the whole file, which is an assertion about the wrong thing and blocks the
# only correct fix for a losing claim.
check "suppressed section is empty after the merge" \
      "awk '/^## Suppressed by baseline/,/^## Out of scope/' '$TRI/absorb.md' | grep -q '_none_'"
check "the absorbed P3 claim rides along instead of vanishing" \
      "grep -q 'also P3/20: .*field length' '$TRI/absorb.md'"
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
"$BIN/jjstack-review-run-report" "$TRI/vendmerge.tsv" --out "$TRI/vendmerge.md" > /dev/null 2> "$TRI/vendmerge.err"
check "POSITIVE CONTROL: merged-up vendor report warns after the merge" \
      "grep -q 'vendor/lib/x.js:5 (vendor) is reported' '$TRI/vendmerge.err'"
# Defence in depth: an all-suppressed group whose merged severity is P0 must
# never render. The per-row check already rejects this input, and the merged
# check rejects it again — invariant 3 must hold on both sides of the collapse.
{
  row P3 20 src/e.py:7 style    suppress baseline 'the parser accepts a header value without any bound'
  row P0 91 src/e.py:7 security suppress baseline 'the parser accepts a header value without checking the signature'
} > "$TRI/absorb2.tsv"
"$BIN/jjstack-review-run-report" "$TRI/absorb2.tsv" --out "$TRI/absorb2.md" > /dev/null 2> "$TRI/absorb2.err"
rc=$?
check "an all-suppressed merge reaching P0 is rejected" "[ $rc -eq 4 ]"
check "merged P0 rejection renders nothing"             "[ ! -f '$TRI/absorb2.md' ]"
# A group that agrees changes nothing, so it must NOT be listed as a merge —
# otherwise the Merges section is noise and nobody reads the real entries.
check "an agreeing dedup is not reported as a merge" "grep -q 'merges-raised=0' '$TRI/good.out'"

# --- REGRESSION: an EQUAL-severity merge discarded the losing claim ---------
# The merge preserved severity and disposition but not the CLAIM. Two DISTINCT
# P0s at one line sharing an opening phrase collapsed to one row: the higher
# confidence was copied onto the OTHER row's sentence, and the losing finding's
# text appeared ZERO times in the report. `RAISED` was set only when severity
# or disposition changed, so an equal/equal merge was invisible in the Merges
# section too, and the tally said report=1 for two reported findings.
# A finding whose text vanishes is a lost finding, whatever the tally says.
{
  row P0 60 src/a.py:10 security report - 'the request handler does not validate the incoming token allowing auth bypass'
  row P0 95 src/a.py:10 memory   report - 'the request handler does not validate the incoming size so double free'
} > "$TRI/eqsev.tsv"
"$BIN/jjstack-review-run-report" "$TRI/eqsev.tsv" --out "$TRI/eqsev.md" > "$TRI/eqsev.out" 2>&1
rc=$?
check "two distinct P0s at one line exit 0"        "[ $rc -eq 0 ]"
check "the winning claim survives an equal merge"  "grep -q 'double free' '$TRI/eqsev.md'"
check "the LOSING claim survives an equal merge"   "grep -q 'auth bypass' '$TRI/eqsev.md'"
# Confidence must be read off the same row as the sentence beside it.
check "confidence belongs to the claim it sits next to" \
      "grep -qE '^\\| P0 \\| 95 \\|.*double free' '$TRI/eqsev.md'"
check "the losing claim keeps its OWN severity and confidence" \
      "grep -q 'also P0/60: .*auth bypass' '$TRI/eqsev.md'"
# An equal/equal merge that drops a claim IS a merge, so it is auditable.
check "an equal-severity claim merge is counted as a merge" \
      "grep -q 'merges-raised=1' '$TRI/eqsev.out'"
check "an equal-severity claim merge is listed in the Merges section" \
      "awk '/^## Merges/,0' '$TRI/eqsev.md' | grep -q 'double free'"
check "the Merges section shows both claims"       \
      "awk '/^## Merges/,0' '$TRI/eqsev.md' | grep -q 'auth bypass'"
# A merge that changes nothing still must not be announced as one.
check "identical claims at one line are still not a merge" "grep -q 'merges-raised=0' '$TRI/good.out'"

# POSITIVE CONTROL 8 — the merged-record checks were unreachable: every one of
# them was implied by the per-row check that ran first (RSN is only ever
# assigned with DISP_ from the SAME row, and DISP_ is the minimum disprank, so
# `suppress` implies every member was already rejected per-row). Deleting the
# whole block left the suite green. They now verify the COLLAPSE against an
# independent member ledger, so the control feeds them a BROKEN COLLAPSE.
# The injected fault is not invented: it is the literal pre-fix dedup body
# recovered from git (d128644^ lines 192-200), which kept the first-seen row
# and discarded the rest — the exact defect this PR exists to fix.
MUT="$TRI/run-report-with-prefix-dedup"
# The script sources its vocabulary from beside itself, so the mutant needs the
# same two files next to it — otherwise it dies at startup and "exit 4" would be
# reporting a missing file, not a rejected collapse.
cp "$BIN/jjstack-review-vocab.sh" "$BIN/jjstack-review-vocab.tsv" "$TRI/"
python3 - "$BIN/jjstack-review-run-report" "$MUT" <<'MUTPY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
a = s.index("    # MERGE, never drop.")
b = s.index("    next\n", a) + len("    next\n")
# git show d128644^:bin/jjstack-review-triage -- the dedup branch was exactly
# the lens bookkeeping followed by a bare `next`.
open(dst, "w", encoding="utf-8").write(s[:a] + "    next\n" + s[b:])
MUTPY
chmod +x "$MUT"
check "the fault injection actually changed the script" "! cmp -s '$MUT' '$BIN/jjstack-review-run-report'"
"$MUT" "$TRI/absorb.tsv" --out "$TRI/mut.md" > /dev/null 2> "$TRI/mut.err"
rc=$?
check "POSITIVE CONTROL: a broken collapse is rejected (exit 4)" "[ $rc -eq 4 ]"
check "the merged-record check names what the collapse lost" \
      "grep -q 'merge lost the highest severity' '$TRI/mut.err'"
check "a broken collapse renders nothing"                       "[ ! -f '$TRI/mut.md' ]"

# --- REGRESSION: an unescaped `|` in a claim shifted the markdown table -----
# `lenslist()` already stripped `|` from the lens column, so the hazard was
# known for one field and missed for the other. A claim quoting `a || b`
# produced a 9-cell row against a 7-cell header and renderers dropped the
# overflow, making the finding text unreadable in the committed artifact.
row P2 50 src/x.py:3 correctness report - 'the guard uses a || b when it should use a && b' > "$TRI/pipe.tsv"
"$BIN/jjstack-review-run-report" "$TRI/pipe.tsv" --out "$TRI/pipe.md" > /dev/null 2>&1
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
"$BIN/jjstack-review-run-report" "$TRI/empty.tsv" --out "$TRI/empty.md" > /dev/null 2> "$TRI/empty.err"
rc=$?
check "an empty ledger still exits 0 unreconciled" "[ $rc -eq 0 ]"
check "empty unreconciled ledger warns it certifies nothing" "grep -q 'certifies nothing' '$TRI/empty.err'"
check "unreconciled header does not claim completeness"      "grep -q 'was NOT verified' '$TRI/empty.md'"
# POSITIVE CONTROL 6 — the same empty ledger against a real adjudicated set
# must refuse to render and name every finding that left without a disposition.
"$BIN/jjstack-review-run-report" "$TRI/empty.tsv" --reconcile "$TRI/adjudicated.jsonl" \
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
"$BIN/jjstack-review-run-report" "$TRI/full.tsv" --reconcile "$TRI/adjudicated.jsonl" \
  --out "$TRI/full.md" > /dev/null 2>&1
rc=$?
check "a complete ledger reconciles (exit 0)"          "[ $rc -eq 0 ]"
check "reconciled header states it is a checked fact"  "grep -q 'checked fact, not a promise' '$TRI/full.md'"
check "reconciled ledger names its adjudicated source" "grep -q 'reconciled against' '$TRI/full.md'"
# A missing adjudicated file is exit 3, the same clean signal as a missing ledger.
"$BIN/jjstack-review-run-report" "$TRI/full.tsv" --reconcile "$TRI/nope.jsonl" > /dev/null 2>&1
rc=$?
check "missing --reconcile file exits 3" "[ $rc -eq 3 ]"

# --- REGRESSION: a documented `path:N-M` location could never reconcile -----
# The header documents `path:line (or range N-M)`, the ledger stored the raw
# string, and the reconciler keys on `file:start_line`. So a range row exited 4
# accusing the ledger of dropping a finding that was sitting right there, and
# the printed remedy ("fix the ledger") was wrong.
row P0 90 src/a.py:10-14 security report - 'auth bypass over a range' > "$TRI/range.tsv"
adj security src/a.py 10 P0 'auth bypass' > "$TRI/range.jsonl"
"$BIN/jjstack-review-run-report" "$TRI/range.tsv" --reconcile "$TRI/range.jsonl" \
  --out "$TRI/range.md" > /dev/null 2> "$TRI/range.err"
rc=$?
check "a path:N-M row reconciles against file:start_line (exit 0)" "[ $rc -eq 0 ]"
check "the range row still renders its own full location" "grep -q 'src/a.py:10-14' '$TRI/range.md'"

# --- REGRESSION: an EMPTY adjudicated set reconciled vacuously --------------
# Reconciling against nothing satisfied every count, printed "a checked fact,
# not a promise", AND suppressed the "certifies nothing" advisory — so the
# reconciled page made a STRONGER claim than the unreconciled one on strictly
# less evidence. Evidence of absence is not a check.
: > "$TRI/emptyadj.jsonl"
"$BIN/jjstack-review-run-report" "$TRI/empty.tsv" --reconcile "$TRI/emptyadj.jsonl" \
  --out "$TRI/vac.md" > /dev/null 2> "$TRI/vac.err"
rc=$?
check "an empty adjudicated set still exits 0"                  "[ $rc -eq 0 ]"
check "reconciling against nothing claims no checked fact"      "! grep -q 'checked fact' '$TRI/vac.md'"
check "reconciling against nothing says so on the page"         "grep -q 'was NOT verified' '$TRI/vac.md'"
check "reconciling against nothing still certifies nothing"     "grep -q 'certifies nothing' '$TRI/vac.err'"

# --- REGRESSION: a crash in the reconciler read as a missing finding --------
# A non-UTF-8 byte made python exit 1 with an empty stdout, which is the same
# signal as "problems found" — so the tool printed "ledger does not account for
# every adjudicated finding" above an EMPTY problem list. A tool that cannot
# run must say it could not run, never blame the input it never read.
printf 'not utf8: \377\376\n' > "$TRI/binary.jsonl"
"$BIN/jjstack-review-run-report" "$TRI/full.tsv" --reconcile "$TRI/binary.jsonl" \
  --out "$TRI/crash.md" > /dev/null 2> "$TRI/crash.err"
rc=$?
check "an unreadable adjudicated file fails loudly (exit 4)"    "[ $rc -eq 4 ]"
check "a crash is not reported as a dropped finding"            "! grep -q 'left the review without a disposition' '$TRI/crash.err'"
check "a crash names the real problem"                          "grep -q 'not valid UTF-8' '$TRI/crash.err'"
check "a failed reconciliation never prints an empty problem list" "[ -s '$TRI/crash.err' ]"
check "a crashed reconciliation renders nothing"                "[ ! -f '$TRI/crash.md' ]"

# --- REGRESSION: --help truncated at a hardcoded line number ----------------
# `sed -n '2,43p'` cut the block before the Exit line, so the documented exit
# codes — including the exit 4 the whole design hinges on — never reached the
# user. The range is now computed from the comment block itself.
"$BIN/jjstack-review-run-report" --help > "$TRI/help.txt" 2>&1
check "--help documents the exit codes"      "grep -q 'Exit: 0 report valid' '$TRI/help.txt'"
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

echo "== 7f. review-ledger (path-glob scope — may DEMOTE, never suppress) =="
# Every reviewer people keep using grows a memory of what was waved off. The
# risk is that the memory quietly becomes a suppression list — which is how a
# recall-first reviewer turns into a precision-first one without anyone
# deciding to. These tests pin the rules that stop that. This is the MIDDLE rung
# of the memory ladder: its key is a path glob plus a category, so its ceiling
# is `demote`.
# Hand-written fixtures below need the store's own two header lines, or
# validate_store rejects the file before the behaviour under test is reached.
LG_HDR=$'#jjstack-review-store\tscope=path-glob\tmax-effect=demote\tv=1'
LG_COLS=$'#ts\trepo\ttype\teffect\tcode\tpath-glob\tcategory\tnote'
LD="$(mktemp -d)/ledger.tsv"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'bin/*' --category style \
  --note 'house style permits it' --ledger "$LD" >/dev/null 2>&1
check "records a dismissal"              "[ -f '$LD' ]"
check "the store declares its scope and ceiling" \
  "head -n 1 '$LD' | grep -q 'scope=path-glob.*max-effect=demote'"
"$BIN/jjstack-review-ledger" --match --path 'bin/foo.sh' --category style --ledger "$LD" > "$LD.hit" 2>/dev/null
check "prior dismissal demotes a repeat"  "[ \$? -eq 0 ]"
check "the match states effect=demote"    "grep -q 'effect=demote' '$LD.hit'"
"$BIN/jjstack-review-ledger" --match --path 'src/foo.py' --category style --ledger "$LD" >/dev/null 2>&1
check "unrelated path does not demote"    "[ \$? -eq 1 ]"

# Rule 1: only dismissals suppress. Suppressing a previously-FIXED issue would
# hide the regression of a bug this repo has already paid for once.
"$BIN/jjstack-review-ledger" --record --type fixed --path 'lib/*' --category performance --ledger "$LD" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'lib/x.py' --category performance --ledger "$LD" >/dev/null 2>&1
check "a FIXED record never suppresses" "[ \$? -eq 1 ]"
# POSITIVE CONTROL — the fixed record must really be on file and really match
# path+category, or the non-suppression proves nothing about the type check.
check "the FIXED record exists and matches path+category" \
  "awk -F'\t' '\$3==\"fixed\" && \$6==\"lib/*\" && \$7==\"performance\"{f=1} END{exit !f}' '$LD'"
# ...and it is recorded with effect `none`: history, not a verdict.
check "a FIXED record carries no effect" \
  "awk -F'\t' '\$3==\"fixed\"{exit !(\$4==\"none\")}' '$LD'"

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
"$BIN/jjstack-review-ledger" --record --type dismissed --path x --category style --code feels-fine --ledger "$LD" >/dev/null 2>&1
check "an invented reason code exits 2" "[ \$? -eq 2 ]"

# Rule 4: a record only speaks about a finding whose PATH it matches. The
# protected branch used to print and `continue` before the glob was ever tested,
# so a dismissal recorded against 'docs/*' announced itself on a security
# finding in 'src/payments.py'. The skill then tells the reviewer to cite that
# prior dismissal in the finding body: a fabricated precedent, pointing at a
# live P0. The pre-existing protected test could not catch it because its glob
# ('src/*' vs 'src/a.py') happened to match.
LDG="$(mktemp -d)/ledger.tsv"
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

# Rule 5b — THE CLASS, not three more spellings. The first guard stripped the
# characters `*?/` and rejected whatever came out empty: a rule shaped exactly
# like the two spellings its fixture happened to contain. `*[a-z]*`, `[a-z]*`
# and `*.*` all sailed through it and all demote effectively every path in the
# repo. Adding those three to the strip set would reproduce the same mistake one
# row further along, because the next spelling nobody thought of still wins.
#
# So the invariant is stated over COMPILED SEMANTICS instead of over syntax: a
# pattern is too broad when it reaches across unrelated parts of the repo. The
# probe corpus below is deliberately disjoint — eight unrelated top-level
# directories plus three root files — and the property asserted is end to end:
#
#   for ANY spelling, either --record refuses it, or the row it wrote does not
#   demote findings under three or more unrelated top-level names.
#
# Every spelling in BLANKETS is one that appears nowhere in the implementation
# (bracket ranges, a negated bracket, a POSIX class, bare `?` runs, nested
# `*/*/*`), so a guard that passes this cannot have been written to its fixture.
BREADTH_PROBE=(src/payments.py lib/util.go docs/guide.md tests/test_api.rb
               .github/workflows/ci.yml vendor/thirdparty/lib.c
               deep/nested/tree/Widget.java Makefile README.md go.mod)
breadth_tops() {    # distinct top-level names the single row in $1 demotes
  local p out=""
  for p in "${BREADTH_PROBE[@]}"; do
    if grep -q '^DEMOTE ' <<< "$("$BIN/jjstack-review-ledger" --match --path "$p" \
         --category style --ledger "$1" 2>/dev/null)"; then
      out="$out${p%%/*}
"
    fi
  done
  printf '%s' "$out" | sort -u | grep -c . | tr -d ' '
}
BLANKETS=('*[a-z]*' '[a-z]*' '*.*' '?*?' '**' '[!q]*' '*[[:alpha:]]*' '??*' '*/*/*' '?*')
blanket_leaks=0; blanket_detail=""
for pat in "${BLANKETS[@]}"; do
  BR="$(mktemp -d)/ledger.md"
  if "$BIN/jjstack-review-ledger" --record --type dismissed --path "$pat" --category style \
       --note 'blanket' --ledger "$BR" >/dev/null 2>&1; then
    reach=$(breadth_tops "$BR")
    if [ "${reach:-0}" -ge 3 ]; then
      blanket_leaks=$((blanket_leaks + 1))
      blanket_detail="$blanket_detail $pat"
    fi
  fi
  rm -rf "$(dirname "$BR")"
done
check "no path glob may demote across 3+ unrelated top-level names${blanket_detail:+ — leaked:$blanket_detail}" \
  "[ $blanket_leaks -eq 0 ]"
# The other half of the property: every one of those spellings must be REFUSED
# at --record, not merely narrow by luck. "Either refused or narrow" is what the
# guard promises; this pins which arm actually fires.
blanket_accepted=""
for pat in "${BLANKETS[@]}"; do
  BR="$(mktemp -d)/ledger.md"
  "$BIN/jjstack-review-ledger" --record --type dismissed --path "$pat" --category style \
    --ledger "$BR" >/dev/null 2>&1 && blanket_accepted="$blanket_accepted $pat"
  rm -rf "$(dirname "$BR")"
done
check "every blanket spelling is refused at --record${blanket_accepted:+ — accepted:$blanket_accepted}" \
  "[ -z \"\$blanket_accepted\" ]"
# POSITIVE CONTROL — the reach probe must actually COUNT, not saturate at one or
# return a constant. A pattern that lands in exactly two unrelated top-level
# names must score 2: below the threshold, so the guard lets it through and the
# measurement is observable end to end. ('[dl]*/[gu]*' hits lib/util.go and
# docs/guide.md and nothing else in the probe corpus.)
BRC="$(mktemp -d)/ledger.md"
"$BIN/jjstack-review-ledger" --record --type dismissed --path '[dl]*/[gu]*' --category style \
  --note 'two tops' --ledger "$BRC" >/dev/null 2>&1
check "positive control: the reach probe scores a two-directory glob as 2" \
  "[ \"\$(breadth_tops '$BRC')\" -eq 2 ]"
# POSITIVE CONTROL — a genuinely scoped row must score narrow, or the threshold
# would be rejecting everything.
BRN="$(mktemp -d)/ledger.md"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'docs/*' --category style \
  --note 'scoped' --ledger "$BRN" >/dev/null 2>&1
check "positive control: a scoped 'docs/*' row reaches exactly one top-level name" \
  "[ \"\$(breadth_tops '$BRN')\" -eq 1 ]"
# And the scoped spellings a reviewer actually writes must still be accepted — a
# breadth rule that rejects 'src/legacy/*' is a rule nobody can use.
scoped_rejects=0
for pat in 'src/legacy/*' 'docs/*' 'tests/**' 'bin/jjstack-review-*' 'src/*/generated/*'; do
  BS="$(mktemp -d)/ledger.md"
  "$BIN/jjstack-review-ledger" --record --type dismissed --path "$pat" --category style \
    --ledger "$BS" >/dev/null 2>&1 || scoped_rejects=$((scoped_rejects + 1))
  rm -rf "$(dirname "$BS")"
done
check "positive control: every scoped glob a reviewer would write is accepted" \
  "[ $scoped_rejects -eq 0 ]"

# Rule 5c — the ledger is designed to be hand-edited in git, so --record is only
# half the door. --match read the pattern straight out of the file, so one
# merged or hand-typed blanket row demoted repo-wide with no check at all.
#
# TWO guards live on the read path and they are deliberately different. A
# pattern of nothing but `*?/` is refused by validate_store: the whole store is
# invalid (exit 4), because that is the shape the migration tool used to launder
# through. The corpus breadth test then catches the blankets that DO carry a
# literal — `*e*` here — which no spelling rule would ever list; that row stays
# in the file as history and is skipped with a warning. Using `*` for this
# fixture would test the first guard twice and leave the second one unproven.
LDH="$(mktemp -d)/ledger.tsv"
printf '%s\n%s\n' "$LG_HDR" "$LG_COLS" > "$LDH"
printf '2026-01-01\tacme/x\tdismissed\tdemote\tprior-decision\t*e*\tstyle\thand written\n' >> "$LDH"
out=$("$BIN/jjstack-review-ledger" --match --path 'src/payments.py' --category style \
  --ledger "$LDH" 2>&1)
check "a hand-edited blanket row does NOT demote" \
  "! grep -q '^DEMOTE ' <<< \"\$out\""
check "a hand-edited blanket row says why it was ignored" \
  "grep -qi 'too broad' <<< \"\$out\""
# ...and the literal-free spelling is refused one level up, by the store guard,
# so neither door is left open.
printf '%s\n%s\n' "$LG_HDR" "$LG_COLS" > "$LDH"
printf '2026-01-01\tacme/x\tdismissed\tdemote\tprior-decision\t*\tstyle\thand written\n' >> "$LDH"
"$BIN/jjstack-review-ledger" --match --path 'src/payments.py' --category style \
  --ledger "$LDH" > "$LDH.out" 2> "$LDH.err"; rc=$?
check "a literal-free glob invalidates the whole store (exit 4)" "[ $rc -eq 4 ]"
check "and it says the glob matches every file"  "grep -q 'matches every file' '$LDH.err'"
check "and nothing is demoted from it"           "! grep -q '^DEMOTE ' '$LDH.out'"
# POSITIVE CONTROL — the same hand-written row shape, scoped, must still demote,
# or "does not demote" would only mean hand-written rows are never read at all.
printf '%s\n%s\n' "$LG_HDR" "$LG_COLS" > "$LDH"
printf '2026-01-01\tacme/x\tdismissed\tdemote\tprior-decision\tsrc/*\tstyle\thand written scoped\n' >> "$LDH"
hedge=$("$BIN/jjstack-review-ledger" --match --path 'src/payments.py' --category style \
  --ledger "$LDH" 2>/dev/null)
check "positive control: a hand-edited SCOPED row still demotes" \
  "grep -q '^DEMOTE ' <<< \"\$hedge\""
rm -rf "$(dirname "$LDH")" "$(dirname "$BRC")" "$(dirname "$BRN")"

# Rule 6: the note is quoted by the skill as the demotion reason, so it must
# survive the round trip whole. The markdown reader took field 6 of a
# '|'-separated line, which truncated any note containing a pipe at the first
# one — silently dropping the condition attached to the dismissal. TSV columns
# make that structural, and this test pins that it stayed fixed.
LDP="$(mktemp -d)/ledger.tsv"
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

# Rule 6b — the pipe fix was, again, exactly as wide as its fixture. The reader
# was taught to rejoin fields 6..NF so a '|' survives; a NEWLINE in the same
# note was untouched, and it is the worse half of the class. `--record` printf's
# $NOTE into a single-line record, so a two-line note becomes two physical
# lines: --match keeps only lines with the date shape, so the continuation is
# dropped in silence — and if the continuation happens to LOOK like a record,
# the note has forged a whole ledger row.
#
# The rule is therefore stated by what is ALLOWED, not by a list of characters
# to strip: a note is stored in the printable alphabet, and anything outside it
# is escaped into that alphabet reversibly. A control character nobody has
# thought of is covered by the same sentence as the one that was reported.
LDN="$(mktemp -d)/ledger.tsv"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
  --note 'safe today
BUT revisit when we drop py38' --ledger "$LDN" >/dev/null 2>&1
check "a note containing a newline writes exactly ONE ledger row" \
  "[ \"\$(grep -cP '^[0-9]{4}-[0-9]{2}-[0-9]{2}\\t' '$LDN')\" = 1 ]"
check "the ledger file itself gains no orphan continuation line" \
  "! grep -q '^BUT revisit' '$LDN'"
"$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style \
  --ledger "$LDN" > "$LDN.out" 2>/dev/null
check "a note containing a newline survives the round trip whole" \
  "grep -q 'BUT revisit when we drop py38' '$LDN.out'"
check "the demotion is still reported on a single line" \
  "[ \"\$(grep -c '^DEMOTE ' '$LDN.out')\" = 1 ] && [ \"\$(wc -l < '$LDN.out')\" = 1 ]"
# And the escape is REVERSIBLE, not merely visible: decoding the stored note
# with printf %b must give back the original bytes, newline included.
note_back=$(sed -n 's/^DEMOTE.*dismissed previously: //p' "$LDN.out")
check "the stored note decodes back to the exact original text" \
  "[ \"\$(printf '%b' \"\$note_back\")\" = \$'safe today\nBUT revisit when we drop py38' ]"

# THE CLASS — a blacklist is how '|' got covered and newline did not, so the
# assertion is over the whole non-printable range, not over three more
# characters. Every control character below must leave one well-formed row and
# must not forge a second one. \033 and \013 appear nowhere in the fix.
ctl_bad=0
for esc in '\n' '\r' '\t' '\013' '\014' '\033' '\007'; do
  LDC="$(mktemp -d)/ledger.tsv"
  n=$(printf "head${esc}2099-01-01\tforged/repo\tdismissed\tdemote\tprior-decision\tsrc/*\tsecurity\tinjected")
  "$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
    --note "$n" --ledger "$LDC" >/dev/null 2>&1
  rows=$(grep -cP '^[0-9]{4}-[0-9]{2}-[0-9]{2}\t' "$LDC")
  [ "$rows" = 1 ] || ctl_bad=$((ctl_bad + 1))
  # the forged row must not be reachable as a security dismissal either
  grep -q 'forged\|injected' \
    <<< "$("$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category security \
           --ledger "$LDC" 2>/dev/null)" && ctl_bad=$((ctl_bad + 1))
  rm -rf "$(dirname "$LDC")"
done
check "no control character in a note can forge a ledger row" "[ $ctl_bad -eq 0 ]"
# POSITIVE CONTROL — the forgery probe must be able to SEE a forged row, or
# "no forgery" would only mean the probe never looks. This row is written
# straight into the file, which is exactly what the unescaped note produced.
LDF="$(mktemp -d)/ledger.tsv"
printf '%s\n%s\n' "$LG_HDR" "$LG_COLS" > "$LDF"
printf '2026-01-01\tacme/x\tdismissed\tdemote\tprior-decision\tdocs/*\tstyle\thead\n' >> "$LDF"
printf '2099-01-01\tforged/repo\tdismissed\tdemote\tprior-decision\tsrc/*\tsecurity\tinjected\n' >> "$LDF"
# (command substitution, not a pipe: --match exits 1 on a PROTECTED-only hit and
# `set -o pipefail` would read that as the whole check failing.)
fout=$("$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category security \
  --ledger "$LDF" 2>/dev/null)
check "positive control: the probe sees a genuinely forged row" \
  "grep -q 'injected' <<< \"\$fout\""
# POSITIVE CONTROL — an ordinary printable note must pass through byte for byte,
# or "escaped" could just mean "mangled". Pipes, quotes, backslashes and
# non-ASCII all stay exactly as typed.
LDA="$(mktemp -d)/ledger.tsv"
plain='keep as-is: 100% "quoted", back\slash, em—dash, pipe | and all'
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
  --note "$plain" --ledger "$LDA" >/dev/null 2>&1
back=$("$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style \
  --ledger "$LDA" 2>/dev/null | sed -n 's/^DEMOTE.*dismissed previously: //p')
check "positive control: a printable note round-trips byte for byte" \
  "[ \"\$(printf '%b' \"\$back\")\" = \"\$plain\" ]"
rm -rf "$(dirname "$LDN")" "$(dirname "$LDF")" "$(dirname "$LDA")"

# Rule 6c — the repo slug is the field that lets a ledger survive being copied
# or merged between repos, so it has to describe the LEDGER's repo. slug() ran
# git in the cwd: recording into project A's ledger from a shell sitting in
# project B stamped every row with B, and the one field that exists to make a
# copied ledger readable became the field that lies about it.
SLA="$(mktemp -d)/repo-a"; SLB="$(mktemp -d)/repo-b"
mkdir -p "$SLA" "$SLB"
git -C "$SLA" init -q 2>/dev/null
git -C "$SLA" remote add origin https://github.com/acme/project-a.git 2>/dev/null
git -C "$SLB" init -q 2>/dev/null
git -C "$SLB" remote add origin https://github.com/acme/project-b.git 2>/dev/null
( cd "$SLB" && "$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' \
    --category style --note 'x' --ledger "$SLA/jjstack/review-ledger.md" ) >/dev/null 2>&1
check "a row is stamped with the LEDGER's repo, not the cwd's" \
  "grep -q 'acme/project-a' '$SLA/jjstack/review-ledger.md'"
check "the cwd's repo does not leak into the stamp" \
  "! grep -q 'acme/project-b' '$SLA/jjstack/review-ledger.md'"
# POSITIVE CONTROL — the two remotes really are different, and the slug really
# is derived from a remote, or both checks above would hold trivially.
check "positive control: the two probe repos have different origins" \
  "[ \"\$(git -C '$SLA' remote get-url origin)\" != \"\$(git -C '$SLB' remote get-url origin)\" ]"
( cd "$SLB" && "$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' \
    --category style --note 'y' --ledger "$SLB/jjstack/review-ledger.md" ) >/dev/null 2>&1
check "positive control: recording into B's own ledger still stamps B" \
  "grep -q 'acme/project-b' '$SLB/jjstack/review-ledger.md'"
# An explicit --repo still wins: it is the caller saying which repo this is.
( cd "$SLB" && "$BIN/jjstack-review-ledger" --record --type dismissed --path 'lib/*' \
    --category style --note 'z' --repo "$SLA" --ledger "$SLB/jjstack/explicit.md" ) >/dev/null 2>&1
check "an explicit --repo still overrides the ledger's location" \
  "grep -q 'acme/project-a' '$SLB/jjstack/explicit.md'"
rm -rf "$(dirname "$SLA")" "$(dirname "$SLB")"

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
for vflag in --type --path --category --code --note --ledger --repo; do
  timeout 5 "$BIN/jjstack-review-ledger" --list "$vflag" >/dev/null 2>&1
  check "ledger $vflag with no value exits 2, never hangs" "[ \$? -eq 2 ]"
done
# POSITIVE CONTROL — `timeout` must really be able to report a hang here, or
# every check above would pass just as well against a script that cannot run.
timeout 2 bash -c 'while :; do :; done' >/dev/null 2>&1
check "positive control: timeout reports a real hang as 124" "[ \$? -eq 124 ]"

# Rule 9: the ladder cap can actually fire. A hand-edited row that claims
# `suppress` from a path-glob key is the exact failure that keeping three stores
# apart prevents.
printf '2026-01-01\t.\tdismissed\tsuppress\tprior-decision\tsrc/*\tstyle\tevil\n' >> "$LD"
"$BIN/jjstack-review-ledger" --validate --ledger "$LD" > /dev/null 2> "$LD.ladder"; rc=$?
check "POSITIVE CONTROL: a ledger row may not suppress (exit 4)" "[ $rc -eq 4 ]"
check "the ladder error names the ceiling" "grep -q \"may emit at most 'demote'\" '$LD.ladder'"
"$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style --ledger "$LD" >/dev/null 2>&1
check "a ladder-violating store is not silently matched" "[ \$? -eq 4 ]"
grep -v '	evil$' "$LD" > "$LD.clean"
"$BIN/jjstack-review-ledger" --validate --ledger "$LD.clean" >/dev/null 2>&1
check "the same store without that row validates clean" "[ \$? -eq 0 ]"

# FIELD-COUNT INTEGRITY ON THE WRITE PATH. Both sibling stores sanitize what
# they write; this one passed --note and --path through untouched. A note
# carrying a newline plus tabs therefore forged an ENTIRE second row — one that
# validates clean, claims a `*` glob, and demotes the whole repo. A per-file
# dismissal silently became a repo-wide one: the widest possible escalation,
# reached through the narrowest-looking command.
LI="$(dirname "$LD")/inject.tsv"
FORGED=$'benign\n2020-01-01\tacme/repo\tdismissed\tdemote\tprior-decision\t*\tstyle\tforged repo-wide demotion'
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/one.py' --category style \
  --code prior-decision --note "$FORGED" --ledger "$LI" >/dev/null 2>&1
check "a newline in --note cannot forge a second row" \
  "[ \"\$(grep -c '^[0-9][0-9][0-9][0-9]-' '$LI')\" -eq 1 ]"
check "no forged repo-wide '*' glob lands in the store" \
  "! awk -F'\t' '\$6==\"*\"{f=1} END{exit !f}' '$LI'"
"$BIN/jjstack-review-ledger" --match --path 'totally/other.py' --category style --ledger "$LI" >/dev/null 2>&1
check "an unrelated file is not demoted by the forged row" "[ \$? -eq 1 ]"
# ...and a tab in --path must not shift every column after it either.
"$BIN/jjstack-review-ledger" --record --type dismissed --path "$(printf 'a\tb')" --category style \
  --code prior-decision --note n --ledger "$LI" >/dev/null 2>&1
check "tabs in --path cannot corrupt the row" \
  "awk -F'\t' '/^[0-9][0-9][0-9][0-9]-/{ if (NF != 8) bad = 1 } END{ exit bad + 0 }' '$LI'"
# POSITIVE CONTROL — a DELIBERATELY recorded WIDE glob does demote across the
# tree it names, so "not demoted" above is about the forgery being blocked, not
# a broken matcher. It cannot be a bare `*`, because `--record` rejects an
# unscoped glob.
#
# This comment used to go on to claim that forgery was therefore "the only way a
# `*` row can reach this store". That was false, and the review that caught it
# was right: `jjstack-review-memory-migrate` converted a legacy `| * |` row
# straight through, `--validate` then said `ok`, and `--match` demoted every path
# in the category. Migration was a second, sanctioned way in, on the one command
# every existing user is told to run. A write-path guard is never the only way in
# while any other tool can write the store — the guard is now on the READ path
# too, in validate_store, which is where every consumer including migrate meets
# it. §7s asserts that, on every entry point.
LW="$(dirname "$LD")/wide.tsv"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 't*' --category style \
  --code prior-decision --note 'deliberate repo-wide' --ledger "$LW" >/dev/null 2>&1
"$BIN/jjstack-review-ledger" --match --path 'totally/other.py' --category style --ledger "$LW" >/dev/null 2>&1
check "POSITIVE CONTROL: a real wide glob does demote across its tree" "[ \$? -eq 0 ]"
# POSITIVE CONTROL — sanitizing must not mangle ordinary notes into uselessness.
check "POSITIVE CONTROL: a benign note is stored verbatim" \
  "awk -F'\t' '\$8==\"deliberate repo-wide\"{f=1} END{exit !f}' '$LW'"

# The same class as the read-path hole in the baseline, at a different seam: a
# plain `while read` DROPS a final line that has no trailing newline, so a store
# whose LAST row claims `suppress` from this demote-capped rung validated `ok`
# — while grep and awk, which every other consumer of the file uses, saw the row
# perfectly well. A validator that reads less of the file than its consumers do
# is worse than none: it certifies exactly the row it failed to look at.
LN="$(dirname "$LD")/nonewline.tsv"
printf '#jjstack-review-store\tscope=path-glob\tmax-effect=demote\tv=1\n' > "$LN"
printf '2026-01-01\t.\tdismissed\tsuppress\tprior-decision\tsrc/*\tstyle\tevil' >> "$LN"
"$BIN/jjstack-review-ledger" --validate --ledger "$LN" >/dev/null 2>&1; rc=$?
check "a violating LAST row with no trailing newline still exits 4" "[ $rc -eq 4 ]"
check "POSITIVE CONTROL: that row really lacks a trailing newline" \
  "[ -n \"\$(tail -c 1 '$LN')\" ]"
# POSITIVE CONTROL — the same file WITH the newline was already caught, so the
# test above measures the missing newline and not merely a broken validator.
printf '\n' >> "$LN"
"$BIN/jjstack-review-ledger" --validate --ledger "$LN" >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: and it is still caught once newline-terminated" "[ $rc -eq 4 ]"
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

echo "== 7h. value-less flags must be a usage error, never a hang =="
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

echo "== 7i. --help is derived from the header, not a hand-kept line range =="
# A `sed -n 'A,Bp'` range drifts the moment a line is added: calibration's help
# stopped mid-sentence and dropped the Usage and Exit sections that usage() sends
# the reader to find, while its two siblings leaked `set -uo pipefail` and the
# raw colour definitions into their own help output.
for tool in jjstack-review-sweep jjstack-review-autofix-diff jjstack-review-calibration \
            jjstack-review-ledger; do
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

echo "== 7j. review-sweep PARTIAL: a check set with no test runner is not clean =="
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

echo "== 7g2. the sweep must read package.json as data, never as code =="
# jjstack-review-sweep spliced $ROOT into a `node -p` JS *string literal* — the
# only detection path that evaluates a path as code. A repo path containing a
# quote ends the literal: at best node throws, the sweep swallows it with
# 2>/dev/null, `scripts` comes back empty and every npm check is silently dropped
# from the plan (a sweep reporting on fewer checks than it should, which is the
# same failure class as calling a partial sweep clean). At worst the path is
# executed: a directory named
#   A'+require('fs').writeFileSync('PWNED','owned')+'
# needs no slash, is a legal directory name, and writes the file. The python3
# fallback two lines below already did it correctly, via argv.
NQS="$(mktemp -d)"; NQD="$NQS/it's a repo"
mkdir -p "$NQD"
printf '{"scripts":{"lint":"echo l","test":"echo t"}}\n' > "$NQD/package.json"
NSHIM="$NQS/shim"; mkdir -p "$NSHIM"
for t in bash node python3; do
  p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$NSHIM/$t"
done
printf '#!/bin/sh\nexit 0\n' > "$NSHIM/npm"; chmod +x "$NSHIM/npm"
nout="$(timeout 30 env PATH="$NSHIM" "$BIN/jjstack-review-sweep" --repo "$NQD" --dry-run 2>&1)"
check "sweep finds npm scripts under a quoted path (lint)" "grep -q 'npm run lint' <<<\"\$nout\""
check "sweep finds npm scripts under a quoted path (test)" "grep -q 'npm run test' <<<\"\$nout\""
# Positive control — the same fixture at an ordinary path must find the same two
# scripts, or the assertions above could pass for want of a working fixture.
NQP="$NQS/plain"; mkdir -p "$NQP"
cp "$NQD/package.json" "$NQP/package.json"
pout="$(timeout 30 env PATH="$NSHIM" "$BIN/jjstack-review-sweep" --repo "$NQP" --dry-run 2>&1)"
check "control: the same fixture at a plain path finds them" \
  "grep -q 'npm run lint' <<<\"\$pout\" && grep -q 'npm run test' <<<\"\$pout\""
# And the path must never be evaluated: a directory name that would execute code
# if spliced into a JS literal must leave no trace behind.
NQX="$NQS/A'+require('fs').writeFileSync('PWNED','owned')+'"
mkdir -p "$NQX"
cp "$NQD/package.json" "$NQX/package.json"
( cd "$NQS" && rm -f PWNED
  timeout 30 env PATH="$NSHIM" "$BIN/jjstack-review-sweep" --repo "$NQX" --dry-run >/dev/null 2>&1 )
check "a hostile path name is never executed as JavaScript" "[ ! -e '$NQS/PWNED' ]"
rm -rf "$NQS"

echo "== 7k. the docs must not teach the deleted rescoring/deletion model =="
# The single guard that existed (a grep for 'delta=' on one command's stdout)
# could not see PROSE, which is exactly how four written copies of the deleted
# model survived a fix that corrected the tool. This guard reads the documents.
# CHANGELOG and README are in scope: the user-facing copy restated the deleted
# model too, and a guard that only reads the skill would let it survive there.
REVDOCS="$DIR/skills/review/SKILL.md $DIR/references/review-post-passes.md $DIR/CHANGELOG.md $DIR/README.md"
REVSRC="$BIN/jjstack-review-sweep $BIN/jjstack-review-autofix-diff $BIN/jjstack-review-calibration"
# A negated grep over a path that no longer resolves EXITS NON-ZERO, and the `!`
# turns that into a PASS — so a rename silently disarms every guard below it.
# SKILL.md, review-post-passes.md and CHANGELOG.md each had a companion positive
# grep that a rename would trip; README.md had none anywhere in the suite, so
# renaming it and re-adding the deleted model left ALL 305 PASS. Assert the
# corpus RESOLVES before asserting anything about its contents.
for f in $REVDOCS $REVSRC; do
  check "guarded doc/source is present: $(basename "$f")" "[ -f '$f' ]"
done
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
# ONE definition of the rescoring/deletion guard, used by the real assertion AND
# by the positive controls below. A control that re-implements the check only
# proves the control matches itself — which is how a dead alternative shipped.
deleted_model_hits() { # deleted_model_hits <file>...
  # Flatten before matching. grep is line-based, and the prose that shipped this
  # model WRAPPED between "adjusts its" and "confidence" — so the pattern could
  # never fire on the very string it was written for, and only the other
  # alternative was ever live. A regex validated against a mental model of the
  # string instead of the string itself is not a guard.
  cat -- "$@" | tr '\n' ' ' | tr -s ' ' \
    | grep -qE 'gets dropped|adjusts its.{0,30}confidence'
}
check "the changelog does not promise findings get dropped or rescored" \
  "! deleted_model_hits '$DIR/CHANGELOG.md'"
check "the changelog documents the PARTIAL sweep state" \
  "grep -qF 'PARTIAL' '$DIR/CHANGELOG.md'"
# Positive controls — the prose guard must be able to fire, or it is a grep over
# documents that can never match and the next copy of the model ships green.
# These are RECOVERED LITERALS, not invented ones: the exact lines that shipped
# the deleted model, taken from CHANGELOG.md at commit 0998a19^. There is one
# control per alternative, because a single control lets a dead alternative hide
# behind a live one.
probe_doc="$(mktemp)"
printf 'repeat false positives decay out of the report\n' > "$probe_doc"
check "prose guard actually catches the deleted model" \
  "grep -qF -- 'decay out' '$probe_doc'"
# Recovered verbatim. This one WRAPS between "adjusts its" and "confidence",
# which is exactly why a line-based grep could never fire on the string it was
# written for. Do not reflow these two lines.
probe_wrap="$(mktemp)"
cat > "$probe_wrap" <<'PROBE'
     repo (`jjstack/review-calibration.tsv`), and the next review adjusts its
     confidence from them — so a false positive you dismissed twice stops being
PROBE
probe_drop="$(mktemp)"
cat > "$probe_drop" <<'PROBE'
     made to fail, the finding was never real and gets dropped — and if it can,
PROBE
check "rescoring guard fires on the prose that shipped it (wrapped line)" \
  "deleted_model_hits '$probe_wrap'"
check "deletion guard fires on the prose that shipped it" \
  "deleted_model_hits '$probe_drop'"
rm -f "$probe_doc" "$probe_wrap" "$probe_drop"

echo "== 7l. --mark is actually invoked, not just implemented =="
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
echo "== 7m. review skill/reference internal consistency =="
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
#
# Both sides are now READ OUT of their file. The previous spelling looped over
# a hardcoded token list and ran one fixed grep that never used `$tok`, so it
# could not tell the two files apart: a bogus `archived` disposition added to
# the skill table kept the suite green, and the reason loop greped the WHOLE
# script — matching the `--help` comment block — so deleting six codes from
# the runtime `split(...)` kept it green too. A guard that does not read the
# thing it guards is decoration.
skill_vocab() {  # $1=file  $2=column index (3=disposition, 4=reason)
  sed -n '/^| Phase 5 outcome | disposition | reason |/,/^$/p' "$1" \
    | awk -F'|' -v c="$2" 'NR > 2 && NF > c { print $c }' \
    | grep -o '`[^`]*`' | tr -d '`' | grep -v '^-$' | sort -u
}
# RUNTIME vocabulary only: the split() string on (or immediately above) the
# line that populates the lookup table. The header comment block, where the
# old grep was matching, is not code and cannot be what the validator uses.
# The populating loop is matched by SHAPE, not by one spelling of it: the
# disposition list became an ordered one (`DISP[DISPORDER[i]] = 1`) while the
# reason list stayed `REASON[a[i]] = 1`, and a guard pinned to the older
# spelling extracts nothing — which reads exactly like a clean vocabulary.
runtime_vocab() {  # $1=script  $2=awk array name (DISP|REASON)
  awk -v want="$2" '
    match($0, /split\("[^"]*"/) { last = substr($0, RSTART + 7, RLENGTH - 8) }
    $0 ~ (want "\\[[A-Za-z_]+\\[i\\]\\] = 1") { print last }
  ' "$1" | tr ' ' '\n' | grep -v '^$' | sort -u
}
# The reason codes moved OUT of the scripts and into the one shared vocabulary
# file — four tools, one list — so that is where the runtime side of the reason
# check reads them from now. Still read out of the artifact, never retyped here.
shared_reasons() { awk -F'\t' '$1 == "reason" { print $2 }' "$BIN/jjstack-review-vocab.tsv" | sort -u; }
VOC="$(mktemp -d)"
skill_vocab   "$SKR" 3                        > "$VOC/skill.disp"
skill_vocab   "$SKR" 4                        > "$VOC/skill.rsn"
runtime_vocab "$BIN/jjstack-review-run-report" DISP > "$VOC/script.disp"
shared_reasons                                     > "$VOC/script.rsn"
# An extraction that silently yields nothing turns every loop below into zero
# assertions, which is the failure mode these guards had in the first place.
check "skill disposition table yields 7 dispositions" "[ \$(wc -l < '$VOC/skill.disp') -eq 7 ]"
check "skill reason table yields 11 reason codes"     "[ \$(wc -l < '$VOC/skill.rsn') -eq 11 ]"
check "script runtime disposition vocabulary has 7"   "[ \$(wc -l < '$VOC/script.disp') -eq 7 ]"
check "shared reason vocabulary has 12 codes"         "[ \$(wc -l < '$VOC/script.rsn') -eq 12 ]"
# skill → script: the model is never told to write a token the validator rejects.
while read -r tok; do
  check "skill disposition \`$tok\` is in the script's RUNTIME vocabulary" \
        "grep -qxF -- '$tok' '$VOC/script.disp'"
done < "$VOC/skill.disp"
while read -r tok; do
  check "skill reason \`$tok\` is in the SHARED vocabulary" \
        "grep -qxF -- '$tok' '$VOC/script.rsn'"
done < "$VOC/skill.rsn"
# script → skill: the validator never accepts a disposition the skill does not
# document, so an invented one cannot enter through either door.
while read -r tok; do
  check "script disposition \`$tok\` is documented in the skill table" \
        "grep -qxF -- '$tok' '$VOC/skill.disp'"
done < "$VOC/script.disp"
rm -rf "$VOC"

echo "== 7n. review-dep-inventory (manifest parsing + vendored-tree exclusion) =="
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

# Assertions read a FILE rather than piping into `grep -q`. That is now belt and
# braces — `check` turns pipefail off around every assertion for the same reason
# (see the helper at the top) — but reading a file is still the clearer shape,
# and it is what the 5d block below does too.
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

# A COMPACT package.json — the form npm, bundlers and generators emit. Every
# dependency group sits on one line. The parser used to open a group by stripping
# its prefix with a GREEDY regex, which consumed through the LAST group opener on
# the line, so on this exact input `react` (the runtime dependency) vanished:
# one row out, exit 0, no warning, and the header eight lines above claimed
# "Handles both pretty-printed and compact package.json". Every stale-API finding
# about the dropped library then fell to "absent from the inventory" and was
# capped at confidence 50 — the phase silently doing nothing while reporting
# success. The old fixture put the groups on separate lines, so the case the
# comment explicitly claimed was never exercised.
DEPC="$(mktemp -d)"; DEPCOUT="$(mktemp)"
printf '{"name":"x","dependencies":{"react":"18.2.0"},"devDependencies":{"vitest":"1.0.0"}}\n' > "$DEPC/package.json"
"$BIN/jjstack-review-dep-inventory" "$DEPC" --tsv > "$DEPCOUT" 2>/dev/null
check "dep-inventory keeps the FIRST group of a compact package.json" \
      "grep -q '^npm	react	18.2.0' '$DEPCOUT'"
check "dep-inventory keeps the LAST group of a compact package.json" \
      "grep -q '^npm	vitest	1.0.0' '$DEPCOUT'"
# Positive control: the fixture really is compact — one line carrying BOTH
# group openers. Split across lines it would pass even with the greedy bug.
check "compact fixture really puts both groups on one line (control)" \
      "[ \"\$(grep -c 'devDependencies' '$DEPC/package.json')\" = 1 ] && [ \"\$(wc -l < '$DEPC/package.json')\" = 1 ] && grep -q 'dependencies.*devDependencies' '$DEPC/package.json'"

# A manifest under a path containing `#`. The relative path used to be spliced
# raw into `sed "s#\t\$m\$#\t\$rel#"` — `#` was the delimiter, so the s-command
# terminated early ("sed: unknown option to `s'"), ZERO rows were written and the
# run fell through to a non-zero exit. Directories like `build#42` are ordinary
# in CI checkouts. The path now goes in via `awk -v`, which needs no escaping.
DEPH="$(mktemp -d)"; DEPHOUT="$(mktemp)"
mkdir -p "$DEPH/build#42"
printf 'module example.com/x\nrequire (\n\tgithub.com/stretchr/testify v1.8.4\n)\n' > "$DEPH/build#42/go.mod"
"$BIN/jjstack-review-dep-inventory" "$DEPH" --tsv > "$DEPHOUT" 2>/dev/null
check "dep-inventory exits 0 under a path containing #" "[ \$? -eq 0 ]"
check "dep-inventory parses a manifest under a # path" \
      "grep -q '^go	github.com/stretchr/testify	v1.8.4' '$DEPHOUT'"
check "dep-inventory reports the # path verbatim, unmangled" \
      "grep -q 'build#42/go.mod\$' '$DEPHOUT'"
# Positive control: regex metacharacters in a path are equally fatal to a raw
# sed splice, and equally invisible to a fixture that has none.
DEPM="$(mktemp -d)"; DEPMOUT="$(mktemp)"
mkdir -p "$DEPM/a.b[1]"
printf 'module example.com/y\nrequire (\n\tgithub.com/pkg/errors v0.9.1\n)\n' > "$DEPM/a.b[1]/go.mod"
"$BIN/jjstack-review-dep-inventory" "$DEPM" --tsv > "$DEPMOUT" 2>/dev/null
check "dep-inventory survives regex metacharacters in a path (control)" \
      "grep -q 'a.b\\[1\\]/go.mod\$' '$DEPMOUT'"

# "Manifests exist but nothing parsed" is a PARSE FAILURE and must not share an
# exit code with "this repo declares nothing external". They are opposite
# conclusions, and SKILL.md tells the model exit 3 is normal — so conflating them
# turned every parser bug into a green light. Exit 4 now, with its own message.
DEPN="$(mktemp -d)"
printf '{"name":"x","version":"1.0.0"}\n' > "$DEPN/package.json"
"$BIN/jjstack-review-dep-inventory" "$DEPN" --tsv >/dev/null 2>&1
check "dep-inventory exits 4 when manifests parse to nothing" "[ \$? -eq 4 ]"
# Positive control: the two states must be DISTINGUISHABLE, not merely non-zero.
"$BIN/jjstack-review-dep-inventory" "$DEPEMPTY" >/dev/null 2>&1
check "no-manifests is still 3, so 3 and 4 are distinguishable (control)" "[ \$? -eq 3 ]"

# A lone `--depth` used to spin forever at 100% CPU: `shift 2` with one argument
# left is a no-op and `set -e` is off, so the loop re-read the same flag. Verified
# 124 under `timeout 3` with zero bytes written. It must be a usage error.
timeout 5 "$BIN/jjstack-review-dep-inventory" --depth >/dev/null 2>&1
check "dep-inventory rejects a valueless --depth instead of hanging" "[ \$? -eq 2 ]"
# Positive control: the guard must not have been bought by rejecting --depth
# outright — a real depth still works.
"$BIN/jjstack-review-dep-inventory" "$DEPC" --depth 2 --tsv >/dev/null 2>&1
check "dep-inventory still accepts --depth with a value (control)" "[ \$? -eq 0 ]"

# Predictable PID-named temp files in a world-writable directory, created with a
# plain `>` and no O_EXCL (CWE-377), and the find redirect ran BEFORE the cleanup
# trap was installed. Assert the script names no such path any more.
_dep_mktemp=$(grep -c 'mktemp -d' "$BIN/jjstack-review-dep-inventory")
_dep_pid=$(grep -cF '.jjdep.$$' "$BIN/jjstack-review-dep-inventory")
check "dep-inventory creates its scratch with mktemp, not a PID-named path" \
      "[ \"\$_dep_mktemp\" -ge 1 ] && [ \"\$_dep_pid\" = 0 ]"
# Positive control on the GUARD: a probe file carrying the old pattern must be
# caught, or the assertion above passes forever on a grep that matches nothing.
_dep_probe="$(mktemp)"
printf 'x > "${TMPDIR:-/tmp}/.jjdep.$$.manifests"\n' > "$_dep_probe"
_dep_probe_hits=$(grep -cF '.jjdep.$$' "$_dep_probe")
check "the PID-temp-file guard actually catches a \$\$ path (control)" \
      "[ \"\$_dep_probe_hits\" = 1 ]"
# And behaviourally: a run leaves nothing behind in TMPDIR, so the trap covers
# everything the script created — it is now armed BEFORE the first write.
DEPTMP="$(mktemp -d)"
TMPDIR="$DEPTMP" "$BIN/jjstack-review-dep-inventory" "$DEPC" --tsv >/dev/null 2>&1
check "dep-inventory leaves no temp files behind (control)" \
      "[ \"\$(ls -A '$DEPTMP' | wc -l)\" = 0 ]"

rm -rf "$DEP" "$DEPEMPTY" "$DEPOUT" "$DEPC" "$DEPCOUT" "$DEPH" "$DEPHOUT" \
       "$DEPM" "$DEPMOUT" "$DEPN" "$DEPTMP" "$_dep_probe"

echo "== 7o. round-2: refuted needs its document, and disposition rank must be total =="
# Round 2 found the `refuted`/`stale-api` pair — added during a merge-conflict
# resolution — enforcing almost nothing. Two separate defects, both fixed here
# at the level of the CLASS rather than the reported instance.
R2="$(mktemp -d)"
r2row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

# --- INVARIANT 5: a documentary refutation must carry its document -----------
# The reviewer's exact reproducer. `refuted` is the ONLY disposition that takes
# a finding off the report for being WRONG, and SKILL.md justifies letting it
# do that to a P0/P1 — which Invariant 3 forbids `suppress` — solely because it
# "carries external evidence". §4.5b step 3 says the doc URL goes in the claim
# column. Nothing checked. Two tokens and a sentence of opinion bought the same
# effect Invariant 3 exists to deny, and the rendered page then ASSERTED that a
# documentation check happened.
r2row P0 95 src/a.py:7 security refuted stale-api 'I do not think this is real' > "$R2/nourl.tsv"
"$BIN/jjstack-review-run-report" "$R2/nourl.tsv" > "$R2/nourl.out" 2> "$R2/nourl.err"
rc=$?
check "a refuted row with no doc URL is rejected" "[ $rc -eq 4 ]"
check "nothing is rendered for an unevidenced refutation" \
      "! grep -q 'Refuted' '$R2/nourl.out'"
check "the error names the missing evidence" \
      "grep -q 'http' '$R2/nourl.err'"
# CLASS, not instance: the defect is not about P0, or about the security lens.
# A P3 from any lens buys the same unearned deletion, so the guard may not be
# written against the severity or the lens that happened to be reported.
r2row P3 10 docs/x.md:1 style refuted stale-api 'the docs say otherwise, trust me' > "$R2/nourl3.tsv"
"$BIN/jjstack-review-run-report" "$R2/nourl3.tsv" > /dev/null 2> "$R2/nourl3.err"
check "the evidence rule binds every severity, not just P0" "[ \$? -eq 4 ]"
r2row P2 50 src/b.py:2 perf refuted stale-api 'no link here either' > "$R2/nourl2.tsv"
"$BIN/jjstack-review-run-report" "$R2/nourl2.tsv" > /dev/null 2>&1
check "the evidence rule binds every lens, not just security" "[ \$? -eq 4 ]"
# Both URL schemes are documentation; neither is special.
r2row P1 85 src/c.py:3 api refuted stale-api 'correct per https://docs.example/v2/api' > "$R2/https.tsv"
"$BIN/jjstack-review-run-report" "$R2/https.tsv" --out "$R2/https.md" > /dev/null 2>&1
check "a refuted row carrying an https doc URL is accepted" "[ \$? -eq 0 ]"
r2row P1 85 src/c.py:3 api refuted stale-api 'correct per http://docs.example/v2/api' > "$R2/http.tsv"
"$BIN/jjstack-review-run-report" "$R2/http.tsv" --out "$R2/http.md" > /dev/null 2>&1
check "a refuted row carrying an http doc URL is accepted" "[ \$? -eq 0 ]"
# NEGATIVE CONTROL — the new rule must bind `refuted` and nothing else. If it
# leaked onto the other dispositions it would demand a URL from every ordinary
# suppression, and the loop would have no way out.
r2row P2 40 src/d.py:4 sec suppress baseline 'a baselined nit with no link at all' > "$R2/sup.tsv"
"$BIN/jjstack-review-run-report" "$R2/sup.tsv" --out "$R2/sup.md" > /dev/null 2>&1
check "a non-refuted row still needs no URL (negative control)" "[ \$? -eq 0 ]"
# And the same claim text that was REJECTED as a refutation is ACCEPTED as a
# report — proving the rejection is about the disposition's evidence burden,
# not about some incidental property of the string.
r2row P0 95 src/a.py:7 security report - 'I do not think this is real' > "$R2/rep.tsv"
"$BIN/jjstack-review-run-report" "$R2/rep.tsv" --out "$R2/rep.md" > /dev/null 2>&1
check "the identical claim is legal as a report (negative control)" "[ \$? -eq 0 ]"
# The merged record is where the invariants actually bite: a refutation must
# not acquire its evidence by being merged with a differently-worded row.
{ r2row P2 50 src/m.py:1 lensA report - 'shared opening phrase for the merge test here'
  r2row P2 50 src/m.py:1 lensB refuted stale-api 'shared opening phrase for the merge test here'
} > "$R2/mergenourl.tsv"
"$BIN/jjstack-review-run-report" "$R2/mergenourl.tsv" > /dev/null 2> "$R2/mergenourl.err"
check "an unevidenced refutation is caught on the merged record too" "[ \$? -eq 4 ]"

# --- disprank must be TOTAL: no ties, and no order dependence ---------------
# `refuted` was never enumerated in disprank(), so it fell into the `return 5`
# bucket it shares with `suppress`. The merge test is a strict `<`, so first-seen
# won and the SAME input rendered differently depending on row order — with
# `merges-raised=0` in both, so the collapse was invisible. The fix is not "rank
# refuted"; it is that vocabulary and rank come from ONE ordered list, so a
# disposition cannot be added to one and forgotten in the other.
r2disps="report unconfirmed demoted defer suppress out-of-scope refuted"
r2reason() { case "$1" in
    report) echo '-' ;; unconfirmed) echo unverified ;; demoted) echo prior-decision ;;
    defer) echo pre-existing ;; suppress) echo baseline ;; out-of-scope) echo duplicate ;;
    refuted) echo stale-api ;; esac; }
r2claim() { case "$1" in
    refuted) echo 'one shared opening phrase across every disposition https://docs.example/x' ;;
    *) echo 'one shared opening phrase across every disposition' ;; esac; }
# Every unordered PAIR of dispositions, fed in both orders at one location with
# one fingerprint. If any two share a rank, one of these 21 pairs renders
# differently by order. This is the totality proof, not a spot check.
r2_orderfails=0; r2_pairs=0
for a in $r2disps; do for b in $r2disps; do
  [ "$a" \< "$b" ] || continue
  r2_pairs=$((r2_pairs+1))
  { r2row P2 50 src/p.py:1 lensA "$a" "$(r2reason "$a")" "$(r2claim "$a")"
    r2row P2 50 src/p.py:1 lensB "$b" "$(r2reason "$b")" "$(r2claim "$b")"; } > "$R2/ab.tsv"
  { r2row P2 50 src/p.py:1 lensB "$b" "$(r2reason "$b")" "$(r2claim "$b")"
    r2row P2 50 src/p.py:1 lensA "$a" "$(r2reason "$a")" "$(r2claim "$a")"; } > "$R2/ba.tsv"
  # Delete the artifacts first: a run that exits 4 writes nothing, and a stale
  # file from the previous pair would then be compared instead — the comparison
  # would pass on output neither run produced.
  rm -f "$R2/ab.md" "$R2/ba.md" "$R2/ab.out" "$R2/ba.out"
  "$BIN/jjstack-review-run-report" "$R2/ab.tsv" --out "$R2/ab.md" > "$R2/ab.out" 2>/dev/null
  "$BIN/jjstack-review-run-report" "$R2/ba.tsv" --out "$R2/ba.md" > "$R2/ba.out" 2>/dev/null
  [ -f "$R2/ab.md" ] && [ -f "$R2/ba.md" ] || { r2_orderfails=$((r2_orderfails+1)); echo "    pair rendered nothing: $a / $b" >&2; continue; }
  sed 's#^- source findings:.*##' "$R2/ab.md" > "$R2/ab.norm"
  sed 's#^- source findings:.*##' "$R2/ba.md" > "$R2/ba.norm"
  cmp -s "$R2/ab.norm" "$R2/ba.norm" || { r2_orderfails=$((r2_orderfails+1)); echo "    order-dependent pair: $a / $b" >&2; }
  # Compare the TALLY line only: the surrounding stdout names the --out path,
  # which differs between the two runs by construction.
  grep '^.*TALLY' "$R2/ab.out" > "$R2/ab.tally"; grep '^.*TALLY' "$R2/ba.out" > "$R2/ba.tally"
  cmp -s "$R2/ab.tally" "$R2/ba.tally" || { r2_orderfails=$((r2_orderfails+1)); echo "    order-dependent tally: $a / $b" >&2; }
done; done
check "all 21 disposition pairs were exercised" "[ \"\$r2_pairs\" = 21 ]"
check "no two dispositions tie: every pair renders identically in both orders" \
      "[ \"\$r2_orderfails\" = 0 ]"
# The reviewer's own reproducer, spelled out, so the regression has a name.
{ r2row P2 50 src/b.py:3 lensA suppress baseline 'the same defect described the same way here'
  r2row P2 50 src/b.py:3 lensB refuted stale-api 'the same defect described the same way here https://docs.example/y'
} > "$R2/o1.tsv"
{ r2row P2 50 src/b.py:3 lensB refuted stale-api 'the same defect described the same way here https://docs.example/y'
  r2row P2 50 src/b.py:3 lensA suppress baseline 'the same defect described the same way here'
} > "$R2/o2.tsv"
"$BIN/jjstack-review-run-report" "$R2/o1.tsv" --out "$R2/o1.md" > "$R2/o1.out" 2>/dev/null
"$BIN/jjstack-review-run-report" "$R2/o2.tsv" --out "$R2/o2.md" > "$R2/o2.out" 2>/dev/null
check "refuted vs suppress lands in the same section in both orders" \
      "[ \"\$(grep -c '^## Refuted.*(1)' '$R2/o1.md')\" = \"\$(grep -c '^## Refuted.*(1)' '$R2/o2.md')\" ]"
check "refuted vs suppress reports the same tally in both orders" \
      "[ \"\$(grep -o 'TALLY.*' '$R2/o1.out')\" = \"\$(grep -o 'TALLY.*' '$R2/o2.out')\" ]"
# A collapse that changed the disposition is a decision about what the reader
# sees, so it belongs in Merges. Both runs reported merges-raised=0 while
# silently discarding one member's disposition.
check "a disposition-changing collapse is listed in Merges" \
      "! grep -q 'merges-raised=0' '$R2/o1.out'"
check "and is listed in Merges whichever order it arrives in" \
      "! grep -q 'merges-raised=0' '$R2/o2.out'"

# Determinism is a property of the WHOLE page, not just of merges: the same SET
# of findings must render byte-identically however the rows are ordered. Seven
# findings at seven locations, forward and reversed.
: > "$R2/fwd.tsv"
for d in $r2disps; do
  r2row P2 50 "src/z_$d.py:1" "lens_$d" "$d" "$(r2reason "$d")" "$d finding text $( [ "$d" = refuted ] && echo 'https://docs.example/z' )" >> "$R2/fwd.tsv"
done
tac "$R2/fwd.tsv" > "$R2/rev.tsv"
"$BIN/jjstack-review-run-report" "$R2/fwd.tsv" --out "$R2/fwd.md" > "$R2/fwd.out" 2>/dev/null
"$BIN/jjstack-review-run-report" "$R2/rev.tsv" --out "$R2/rev.md" > "$R2/rev.out" 2>/dev/null
sed 's#^- source findings:.*##' "$R2/fwd.md" > "$R2/fwd.norm"
sed 's#^- source findings:.*##' "$R2/rev.md" > "$R2/rev.norm"
check "the rendered ledger is a function of the finding SET, not the row order" \
      "cmp -s '$R2/fwd.norm' '$R2/rev.norm'"
check "and so is the tally line" \
      "[ \"\$(grep -o 'TALLY.*' '$R2/fwd.out')\" = \"\$(grep -o 'TALLY.*' '$R2/rev.out')\" ]"
# POSITIVE CONTROL on the determinism check itself: it must be able to fail.
# Two DIFFERENT sets must not compare equal, or `cmp -s` above proves nothing.
sed 's/z_report/z_reportX/' "$R2/fwd.tsv" > "$R2/other.tsv"
"$BIN/jjstack-review-run-report" "$R2/other.tsv" --out "$R2/other.md" > /dev/null 2>/dev/null
sed 's#^- source findings:.*##' "$R2/other.md" > "$R2/other.norm"
check "the determinism comparison can distinguish two different sets (control)" \
      "! cmp -s '$R2/fwd.norm' '$R2/other.norm'"

# STRUCTURAL: one ordered list is both the vocabulary and the rank, so the two
# physically cannot drift again. A disposition added to the vocabulary without a
# rank is what produced the tie in the first place.
check "the script derives disposition rank from the vocabulary list" \
      "grep -q 'DRANK\[' '$BIN/jjstack-review-run-report'"
check "no disposition falls into an unranked default bucket" \
      "! grep -qE 'return 5[[:space:]]*# suppress' '$BIN/jjstack-review-run-report'"
rm -rf "$R2"


echo "== 7p. round-2: dep-inventory — the TSV contract, and the dialects it advertises =="
# Round 1 replaced a sed-based path substitution with `awk -v`, which fixed the
# `#`-in-path crash and traded it for a different metacharacter bug: awk -v
# performs ESCAPE-SEQUENCE PROCESSING on its value. The fixtures covered `#` and
# `a.b[1]` — the shapes the OLD mechanism was sensitive to — and none covered
# the shape the NEW one is.
D2="$(mktemp -d)"
# Field-aware row lookup. `grep '^pypi\tname\t'` does NOT mean a tab in a BRE,
# so a pattern like that silently matches nothing and every assertion built on
# it passes or fails for the wrong reason. Compare the actual TSV fields.
deprow() { # deprow <tsv> <eco> <name> [version]
  awk -F'\t' -v e="$2" -v n="$3" -v v="${4:-}" \
      '$1 == e && $2 == n && (v == "" || $3 == v) { found = 1 } END { exit !found }' "$1"
}

# --- the 4-field TSV contract, against a path that fights back --------------
# A directory literally named `x\ty` (backslash, t) is a legal path. Passed
# through `awk -v`, the two characters become a TAB, so the manifest column
# splits and the row carries FIVE fields against a documented four. Anything
# consuming `--tsv` by column then reads a truncated path, or a version where
# it expects a manifest.
mkdir -p "$D2/repo/x\\ty"
printf 'module m\n\nrequire (\n\tgithub.com/foo/bar v1.2.3\n)\n' > "$D2/repo/x\\ty/go.mod"
"$BIN/jjstack-review-dep-inventory" "$D2/repo" --tsv > "$D2/bs.tsv" 2>/dev/null
check "a backslash-t path still yields a row" "[ -s '$D2/bs.tsv' ]"
check "every --tsv row has exactly 4 fields, whatever the path holds" \
      "[ \"\$(awk -F'\\t' '{print NF}' '$D2/bs.tsv' | sort -u | tr -d '\\n')\" = 4 ]"
check "the manifest column is the real path, not an escape-processed one" \
      "awk -F'\\t' '{print \$4}' '$D2/bs.tsv' | grep -qF 'x\\ty/go.mod'"
# CLASS: the field count is a contract, so it is asserted for EVERY row of a
# mixed-ecosystem run, not only for the path that happened to be reported.
mkdir -p "$D2/many"
printf '{"dependencies":{"react":"18.2.0"}}\n' > "$D2/many/package.json"
printf 'fastapi==0.110.1\n' > "$D2/many/requirements.txt"
printf 'module m\nrequire github.com/x/y v1.0.0\n' > "$D2/many/go.mod"
"$BIN/jjstack-review-dep-inventory" "$D2/many" --tsv > "$D2/many.tsv" 2>/dev/null
check "the 4-field contract holds across every ecosystem in one run" \
      "[ \"\$(awk -F'\\t' '{print NF}' '$D2/many.tsv' | sort -u | tr -d '\\n')\" = 4 ]"
# And the contract is a GUARD, not just an expectation. Sanitising the path
# fixes the route that was reported; the field separator can also arrive from
# inside the manifest, which the repo controls. A dependency name holding a raw
# tab makes a parser emit a five-field row, and a consumer reading `--tsv` by
# column would then take the version for a manifest. The run must refuse.
mkdir -p "$D2/tabname"
printf '{"dependencies":{"a\tb":"1.0.0"}}\n' > "$D2/tabname/package.json"
"$BIN/jjstack-review-dep-inventory" "$D2/tabname" --tsv > "$D2/tab.out" 2> "$D2/tab.err"
check "a manifest that injects a tab is refused, not shipped" "[ \$? -eq 4 ]"
check "and nothing is emitted on stdout for a consumer to misread" "[ ! -s '$D2/tab.out' ]"
check "the refusal names the contract it is protecting" \
      "grep -q '4-field' '$D2/tab.err'"
# CONTROL — the identical manifest without the tab parses cleanly, so the
# refusal above is about the field count and not about package.json in general.
mkdir -p "$D2/tabok"
printf '{"dependencies":{"ab":"1.0.0"}}\n' > "$D2/tabok/package.json"
"$BIN/jjstack-review-dep-inventory" "$D2/tabok" --tsv > "$D2/tabok.tsv" 2>/dev/null
check "the same manifest without the tab is accepted (control)" \
      "deprow '$D2/tabok.tsv' npm ab 1.0.0"

# --- pyproject: extras truncate the list -----------------------------------
# `if ($0 ~ /\]/) inarr = 0` closed the array on ANY `]`, including the one
# inside an extras spec. Extras are ubiquitous and usually appear early, so
# `"celery[redis]>=5.0"` on the first line silently discarded the whole rest of
# the dependency list — exit 0, no warning, and every stale-API finding about
# the dropped libraries then read as "absent from the inventory".
mkdir -p "$D2/py"
cat > "$D2/py/pyproject.toml" <<'EOF'
[project]
name = "demo"
dependencies = [
  "celery[redis]>=5.0",
  "fastapi>=0.100",
  "httpx",
]

[project.optional-dependencies]
test = ["pytest>=8.0"]

[tool.poetry.group.dev.dependencies]
ruff = "^0.5"

[tool.poetry.dev-dependencies]
black = "^24.1"
EOF
"$BIN/jjstack-review-dep-inventory" "$D2/py" --tsv > "$D2/py.tsv" 2>/dev/null
check "an extras spec does not close the dependency array"  "deprow '$D2/py.tsv' pypi celery" 
check "the entry AFTER an extras spec survives"             "deprow '$D2/py.tsv' pypi fastapi" 
check "and so does an unpinned entry after it"              "deprow '$D2/py.tsv' pypi httpx" 
check "extras are stripped from the package name"           "! grep -q 'celery\\[' '$D2/py.tsv'"
# NEGATIVE CONTROL on deprow itself — a lookup for a package the fixture does
# not declare must FAIL, or every assertion above passes on a broken helper.
check "deprow does not match a package that is absent (control)" \
      "! deprow '$D2/py.tsv' pypi definitely-not-declared"
# Dialect gaps: both of these are standard Poetry and neither matched the
# one-optional-segment regex.
check "poetry group dependencies are parsed (Poetry 1.2+)"  "deprow '$D2/py.tsv' pypi ruff" 
check "legacy poetry dev-dependencies are parsed"           "deprow '$D2/py.tsv' pypi black" 
check "PEP 621 optional-dependencies are parsed"            "deprow '$D2/py.tsv' pypi pytest" 

# --- Cargo: [dependencies.<name>] subtables --------------------------------
# The dotted-subtable form is how every dependency with features is written.
# `/^\[/ { indep = 0 }` closed the section on it, so the dependency vanished.
mkdir -p "$D2/rs"
cat > "$D2/rs/Cargo.toml" <<'EOF'
[package]
name = "demo"

[dependencies]
serde = "1.0"

[dependencies.tokio]
version = "1.35"
features = ["full"]
EOF
"$BIN/jjstack-review-dep-inventory" "$D2/rs" --tsv > "$D2/rs.tsv" 2>/dev/null
check "a plain cargo dependency is still parsed"    "deprow '$D2/rs.tsv' cargo serde 1.0" 
check "a [dependencies.<name>] subtable is parsed"  "deprow '$D2/rs.tsv' cargo tokio 1.35" 

# --- pom.xml and Gemfile: advertised in the header, never fixtured ---------
# The compact one-line form is the SAME class the package.json parser was fixed
# for in round 1 — and the fix was applied only to package.json, because that is
# the only place the fixture looked.
mkdir -p "$D2/jv"
cat > "$D2/jv/pom.xml" <<'EOF'
<project>
  <dependencies>
    <dependency>
      <groupId>org.junit</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>5.10.0</version>
    </dependency>
    <dependency><groupId>com.google.guava</groupId><artifactId>guava</artifactId><version>33.0.0-jre</version></dependency>
  </dependencies>
</project>
EOF
"$BIN/jjstack-review-dep-inventory" "$D2/jv" --tsv > "$D2/jv.tsv" 2>/dev/null
check "a pretty-printed pom dependency is parsed"   "deprow '$D2/jv.tsv' maven junit-jupiter 5.10.0" 
check "a compact one-line pom dependency is parsed" "deprow '$D2/jv.tsv' maven guava 33.0.0-jre" 
mkdir -p "$D2/rb"
cat > "$D2/rb/Gemfile" <<'EOF'
source "https://rubygems.org"
gem "rails", "~> 7.1"
gem "puma"
gem "pg", require: false
EOF
"$BIN/jjstack-review-dep-inventory" "$D2/rb" --tsv > "$D2/rb.tsv" 2>/dev/null
check "a pinned gem is parsed"        "deprow '$D2/rb.tsv' rubygems rails '~> 7.1'" 
check "an unpinned gem is parsed"     "deprow '$D2/rb.tsv' rubygems puma '*'" 
check "a gem with options is parsed"  "deprow '$D2/rb.tsv' rubygems pg" 
rm -rf "$D2"


echo "== 7q. round-2: the change log has no duplicated section =="
# The PR whose own commit message reads "merge the duplicate changelog section"
# shipped `### Changed` twice, verbatim, inside `## [Unreleased]` — lines
# 294-330 and 332-368 byte-identical. A promise in a commit message is not a
# check; this is the check. It is written against the CLASS — no `###` heading
# may repeat inside any `##` section, in any release, ever — not against the
# one heading that regressed.
CL="$DIR/CHANGELOG.md"
check "CHANGELOG.md exists to be checked" "[ -f '$CL' ]"
cl_dupes=$(awk '
  /^## / { section = $0; delete seen; next }
  /^### / { if (seen[$0]++) print section " :: " $0 }
' "$CL")
check "no '###' heading repeats within a CHANGELOG section" "[ -z \"\$cl_dupes\" ]"
[ -n "$cl_dupes" ] && printf '    duplicate: %s\n' "$cl_dupes" >&2
# And no two blocks of it are byte-identical: a merge can reproduce the body
# under two DIFFERENT headings, which the check above would not see.
cl_dupbody=$(awk '
  /^### / { if (n > 0) { b = ""; for (i = 1; i <= n; i++) b = b lines[i] "\n"; if (body[b]++ && b != "\n") print "duplicate body under " head } head = $0; n = 0; next }
  /^## /  { n = 0; head = ""; next }
  head != "" { lines[++n] = $0 }
' "$CL")
check "no CHANGELOG section body is duplicated verbatim" "[ -z \"\$cl_dupbody\" ]"
# POSITIVE CONTROL — the probe is the REAL file with one of its own `###`
# sections appended a second time. Nothing here is invented: the heading and the
# body are the shipped literals, and the guard is the same awk program.
cl_probe="$(mktemp)"
cat "$CL" > "$cl_probe"
awk '
  /^### / { if (grab) exit; grab = 1; print; next }
  grab && /^#/ { exit }
  grab { print }
' "$CL" >> "$cl_probe"
check "the changelog probe was seeded from the shipped file" \
      "[ \"\$(wc -l < '$cl_probe')\" -gt \"\$(wc -l < '$CL')\" ]"
cl_probe_dupes=$(awk '
  /^## / { section = $0; delete seen; next }
  /^### / { if (seen[$0]++) print section " :: " $0 }
' "$cl_probe")
check "the duplicate-heading guard actually catches a duplicate (control)" \
      "[ -n \"\$cl_probe_dupes\" ]"
rm -f "$cl_probe"

echo "== 7r. review memory: one vocabulary, one directory, one format =="
# Seven PRs built /review in parallel and four of them independently grew a
# "remember what the team decided" store. Three of those are real and must stay
# apart — they are an escalation ladder, not four copies of one idea — and the
# fourth was never memory at all. This section pins the consolidation.
VOCAB="$BIN/jjstack-review-vocab.tsv"
check "the shared vocabulary file exists" "[ -f '$VOCAB' ]"
# The ladder, as DATA. If these three rows change, the whole property changes,
# so they are asserted literally rather than paraphrased.
check "calibration's key is the widest, so its ceiling is rank" \
  "grep -q '^scope	pattern-class	rank	' '$VOCAB'"
check "the ledger's key is narrower, so it may demote" \
  "grep -q '^scope	path-glob	demote	' '$VOCAB'"
check "only the instance-keyed baseline may suppress" \
  "grep -q '^scope	instance	suppress	' '$VOCAB'"
# ONE definition. A tool that carries its own copy of the reason codes is a
# fourth vocabulary, which is what this consolidation removed.
for t in jjstack-review-run-report jjstack-review-ledger jjstack-review-calibration; do
  check "$t reads the shared vocabulary" \
    "grep -q 'jjstack-review-vocab.sh' '$BIN/$t'"
done
check "the baseline reads the shared vocabulary" \
  "grep -q 'jjstack-review-vocab.tsv' '$BIN/jjstack-review-baseline'"
n_vocab=$(grep -rlc '^reason	unverified	' "$BIN" 2>/dev/null | wc -l)
check "exactly one file defines the reason codes" "[ \"\$n_vocab\" -eq 1 ]"
# The stale-API disposition of Phase 4.5b is part of that ONE list too: a
# `refuted` finding needs a reason code, and inventing a private one here would
# be the fourth vocabulary all over again.
check "stale-api lives in the shared vocabulary" "grep -q '^reason	stale-api	' '$VOCAB'"
# One directory, three files. Collapsing them into one is the mistake this
# consolidation deliberately did NOT make.
for t in jjstack-review-baseline jjstack-review-ledger jjstack-review-calibration; do
  check "$t stores under jjstack/review-memory/" \
    "grep -q 'jjstack/review-memory' '$BIN/$t'"
done
# One format: TSV. All three default store paths end in .tsv — the whole point
# is that a decision is one line, so it diffs and it greps.
check "the baseline's default store is TSV" \
  "grep -q 'review-memory\", \"baseline.tsv' '$BIN/jjstack-review-baseline'"
check "the ledger's default store is TSV" \
  "grep -q 'review-memory/ledger.tsv' '$BIN/jjstack-review-ledger'"
check "calibration's default store is TSV" \
  "grep -q 'review-memory/calibration.tsv' '$BIN/jjstack-review-calibration'"

echo "== 7s. THE DOUBLE-DEMOTION TEST (demotions never stack into a suppression) =="
# The one test the external review asked for first. Two independent mechanisms
# can demote the same finding: a ledger match (path glob + category) and a
# negative calibration rank (global pattern class). A finding hit by BOTH is
# demoted exactly ONCE — still active, still printed, never suppressed. If
# demotions could compound, two wide heuristics would add up to the suppression
# that only an instance-keyed baseline with a human reason is allowed to make.
DD="$(mktemp -d)"
DD_LED="$DD/ledger.tsv"; DD_CAL="$DD/calibration.tsv"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
  --note 'house style' --ledger "$DD_LED" >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$DD_CAL" --key 'trailing-whitespace' \
  --verdict rejected --code style-only >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$DD_CAL" --key 'trailing-whitespace' \
  --verdict rejected --code style-only >/dev/null 2>&1

led_out=$("$BIN/jjstack-review-ledger" --match --path 'src/a.py' --category style --ledger "$DD_LED" 2>/dev/null)
cal_out=$("$BIN/jjstack-review-calibration" suggest --store "$DD_CAL" --key 'trailing-whitespace' 2>&1)
# Both mechanisms fire on the same finding — the precondition for the test.
check "PRECONDITION: the ledger demotes this finding"   "grep -q 'DEMOTE' <<<\"\$led_out\""
check "PRECONDITION: calibration also demotes it"       "grep -q 'placement=demoted' <<<\"\$cal_out\""
# ...and neither one, hit twice, escalates. `effect=` is stated on both so the
# claim is checkable rather than implied.
check "the ledger hit's effect is exactly demote"       "grep -q 'effect=demote' <<<\"\$led_out\""
check "the calibration hit's effect is only rank"       "grep -q 'effect=rank' <<<\"\$cal_out\""
check "neither mechanism ever emits suppress"           "! grep -q 'suppress' <<<\"\$led_out\$cal_out\""

# THE ROWS FED TO THE REPORT ARE DERIVED FROM WHAT THE TWO MECHANISMS PRINTED.
# This section used to hand-write the `demoted` row it then measured, so its five
# headline assertions read a literal and could not go red for ANY change to
# either demotion mechanism — the section was measuring its own fixture. It now
# translates each mechanism's OWN printed verb into a disposition, one row per
# mechanism that says it demotes. Same location, same claim, so the report must
# merge them into ONE finding, which is precisely the claim under test.
disp_for() {   # disp_for EFFECT — the report disposition that verb earns
  case "$1" in
    suppress)    printf 'suppress\tbaseline\n' ;;
    demote|rank) printf 'demoted\tprior-decision\n' ;;
    *)           printf 'report\t-\n' ;;
  esac
}
effect_of() { sed -n 's/.*effect=\([a-z]*\).*/\1/p' <<<"$1" | head -1; }
DD_CLAIM='trailing whitespace on a long line'
DD_TSV="$DD/findings.tsv"
: > "$DD_TSV"
if grep -q '^DEMOTE ' <<<"$led_out"; then
  printf 'P2\t55\tsrc/a.py:7\tstyle\t%s\t%s\n' \
    "$(disp_for "$(effect_of "$led_out")")" "$DD_CLAIM" >> "$DD_TSV"
fi
if grep -q 'placement=demoted' <<<"$cal_out"; then
  printf 'P2\t55\tsrc/a.py:7\tstyle\t%s\t%s\n' \
    "$(disp_for "$(effect_of "$cal_out")")" "$DD_CLAIM" >> "$DD_TSV"
fi
check "both mechanisms contributed a row, neither typed by hand" \
  "[ \"\$(wc -l < '$DD_TSV')\" -eq 2 ]"
check "the ledger's derived row demotes rather than suppresses" \
  "awk -F'\t' 'NR==1{ exit !(\$5 == \"demoted\") }' '$DD_TSV'"
check "no row derived from a memory store claims a suppression" \
  "! awk -F'\t' '\$5 == \"suppress\" { f = 1 } END { exit !f }' '$DD_TSV'"
# POSITIVE CONTROL — the derivation is not a constant. Fed a `suppress` verb it
# really does produce a suppressing row, and fed `none` it produces no demotion
# at all, so the two assertions above are facts about what the stores printed
# rather than about a translation that can only ever say one thing.
check "POSITIVE CONTROL: the derivation maps 'suppress' to a suppressing row" \
  "[ \"\$(disp_for suppress)\" = \"\$(printf 'suppress\tbaseline')\" ]"
check "POSITIVE CONTROL: and 'none' to no demotion at all" \
  "[ \"\$(disp_for none)\" = \"\$(printf 'report\t-')\" ]"

# The finding, carrying BOTH demotions, is rendered once — in the Demoted
# section, active, with its own severity and confidence intact. Not in the
# suppressed section, not twice, not gone.
"$BIN/jjstack-review-run-report" "$DD_TSV" --out "$DD/report.md" > "$DD/report.out" 2>/dev/null
check "a doubly-demoted finding is still rendered"  "grep -q 'trailing whitespace on a long line' '$DD/report.md'"
check "it is demoted exactly ONCE"                  "[ \"\$(grep -c 'trailing whitespace on a long line' '$DD/report.md')\" -eq 1 ]"
check "it is counted as demoted, not suppressed"    "grep -q 'demoted=1 defer=0 suppress=0' '$DD/report.out'"
check "it keeps its own severity and confidence"    "grep -qE '\\| P2 \\| 55 \\|' '$DD/report.md'"
check "the suppressed section stays empty"          "awk '/^## /{f=0} /^## Suppressed by baseline/{f=1;next} f&&/^_none_/{ok=1} END{exit !ok}' '$DD/report.md'"

# POSITIVE CONTROL — the assertions above must be able to fail. The SAME finding
# marked `suppress` really does land in the suppressed section and out of the
# demoted count, so "demoted=1 suppress=0" is a fact about the double demotion
# rather than about a report that can only ever say one thing.
printf 'P2\t55\tsrc/a.py:7\tstyle\tsuppress\tbaseline\ttrailing whitespace on a long line\n' > "$DD/sup.tsv"
"$BIN/jjstack-review-run-report" "$DD/sup.tsv" --out "$DD/sup.md" > "$DD/sup.out" 2>/dev/null
check "POSITIVE CONTROL: a suppressed finding counts as suppressed" \
  "grep -q 'demoted=0 defer=0 suppress=1' '$DD/sup.out'"
check "POSITIVE CONTROL: and the suppressed section is not empty" \
  "! awk '/^## /{f=0} /^## Suppressed by baseline/{f=1;next} f&&/^_none_/{ok=1} END{exit !ok}' '$DD/sup.md'"
# And the escalation the whole ladder forbids: neither wide store can produce
# that suppression in the first place.
"$BIN/jjstack-review-calibration" record --store "$DD_CAL" --key 'x' --verdict rejected \
  --code not-reachable >/dev/null 2>&1; rc=$?
check "a wide store records a weaker-capped reason without escalating" "[ $rc -eq 0 ]"
check "and the row it wrote still says effect=rank" \
  "awk -F'\t' '\$2==\"x\"{exit !(\$4==\"rank\")}' '$DD_CAL'"
rm -rf "$DD"

echo "== 7t. review-memory-migrate (legacy stores: instruct, then convert) =="
# The stores do NOT migrate themselves. They are version controlled and their
# whole value is that a change is a reviewed diff, so a tool that silently
# rewrote one mid-review would produce a diff nobody approved. Legacy detected
# => stop, name the command, exit 3.
MG="$(mktemp -d)"
git -C "$MG" init -q . 2>/dev/null
mkdir -p "$MG/jjstack"
printf '#ts\tkey\tverdict\tlens\tfile\tnote\n2026-01-01\tunused-import\trejected\tlint\tsrc/a.py\tnope\n' > "$MG/jjstack/review-calibration.tsv"
printf '# jjstack review ledger\n\n2026-01-02 | org/repo | dismissed | bin/* | style | house style\n2026-01-03 | org/repo | fixed | lib/* | performance | fixed in 12\n' > "$MG/jjstack/review-ledger.md"
printf '{"version":2,"jjstack_version":"0.36.0","rules":[{"path":"vendor/*","reason":"upstream owns it"}],"fingerprints":[{"hash":"sha256:0000000000000000000000000000000000000000000000000000000000000001","lens":"security","file":"src/a.py","message":"m","reason":"accepted 2026-01"}]}\n' > "$MG/.jjstack-review-baseline.json"

"$BIN/jjstack-review-calibration" report --repo "$MG" > /dev/null 2> "$MG/cal.err"; rc=$?
check "a legacy calibration store stops the tool (exit 3)" "[ $rc -eq 3 ]"
check "and names the migrate command" "grep -q 'jjstack-review-memory-migrate' '$MG/cal.err'"
"$BIN/jjstack-review-ledger" --list --repo "$MG" > /dev/null 2> "$MG/led.err"; rc=$?
check "a legacy markdown ledger stops the tool (exit 3)" "[ $rc -eq 3 ]"
check "and names the migrate command" "grep -q 'jjstack-review-memory-migrate' '$MG/led.err'"
"$BIN/jjstack-review-baseline" apply /dev/null --baseline "$MG/jjstack/review-memory/baseline.tsv" \
  > /dev/null 2> "$MG/bl.err"; rc=$?
check "a legacy JSON baseline stops the tool (exit 3)" "[ $rc -eq 3 ]"
check "and names the migrate command" "grep -q 'jjstack-review-memory-migrate' '$MG/bl.err'"

"$BIN/jjstack-review-memory-migrate" --repo "$MG" --dry-run >/dev/null 2>&1
check "--dry-run creates no store" "[ ! -f '$MG/jjstack/review-memory/ledger.tsv' ]"
"$BIN/jjstack-review-memory-migrate" --repo "$MG" >/dev/null 2>&1
check "migrate writes all three stores" \
  "[ -f '$MG/jjstack/review-memory/calibration.tsv' ] && [ -f '$MG/jjstack/review-memory/ledger.tsv' ] && [ -f '$MG/jjstack/review-memory/baseline.tsv' ]"
check "they stay THREE files, not one" \
  "[ \"\$(ls -1 '$MG/jjstack/review-memory' | wc -l)\" -eq 3 ]"
"$BIN/jjstack-review-calibration" validate --repo "$MG" >/dev/null 2>&1
check "the migrated calibration store validates" "[ \$? -eq 0 ]"
"$BIN/jjstack-review-ledger" --validate --repo "$MG" >/dev/null 2>&1
check "the migrated ledger validates" "[ \$? -eq 0 ]"
"$BIN/jjstack-review-baseline" validate --baseline "$MG/jjstack/review-memory/baseline.tsv" >/dev/null 2>&1
check "the migrated baseline validates" "[ \$? -eq 0 ]"
# Both baseline mechanisms survive the JSON->TSV move, each keeping its
# mandatory human reason. Losing either would silently reactivate or silently
# broaden every accepted finding.
check "the fingerprint survives migration" \
  "grep -q 'sha256:0000000000000000000000000000000000000000000000000000000000000001' '$MG/jjstack/review-memory/baseline.tsv'"
check "the glob rule survives migration" \
  "grep -q 'vendor/\\*' '$MG/jjstack/review-memory/baseline.tsv'"
check "each entry keeps its mandatory reason" \
  "grep -q 'accepted 2026-01' '$MG/jjstack/review-memory/baseline.tsv' && grep -q 'upstream owns it' '$MG/jjstack/review-memory/baseline.tsv'"
# The writer's jjstack version must survive too, or the fail-closed drift guard
# that makes stale fingerprints inert stops firing after a migration.
check "the original writer's version survives" \
  "head -n 1 '$MG/jjstack/review-memory/baseline.tsv' | grep -q 'jjstack=0.36.0'"
# The ledger's history rows must NOT gain a verdict they never had.
check "a migrated FIXED row carries effect none" \
  "awk -F'\t' '\$3==\"fixed\"{exit !(\$4==\"none\")}' '$MG/jjstack/review-memory/ledger.tsv'"
check "a migrated dismissal carries effect demote" \
  "awk -F'\t' '\$3==\"dismissed\"{exit !(\$4==\"demote\")}' '$MG/jjstack/review-memory/ledger.tsv'"
# POSITIVE CONTROL — refuse to clobber an existing destination without --force.
"$BIN/jjstack-review-memory-migrate" --repo "$MG" >/dev/null 2>&1
check "POSITIVE CONTROL: a second migrate refuses to clobber (exit 4)" "[ \$? -eq 4 ]"
"$BIN/jjstack-review-memory-migrate" --repo "$MG" --force >/dev/null 2>&1
check "--force overwrites deliberately" "[ \$? -eq 0 ]"
MGE="$(mktemp -d)"
"$BIN/jjstack-review-memory-migrate" --repo "$MGE" >/dev/null 2>&1
check "nothing to migrate is a clean exit 0" "[ \$? -eq 0 ]"
rm -rf "$MG" "$MGE"

echo "== 7u. a value-less flag is a usage error, never a hang (whole family) =="
# `--flag` with no value used to spin forever. bash's `shift 2` is a NO-OP when
# fewer than two arguments remain — shift FAILS when n > $# rather than shifting
# what it can — and `set -e` is deliberately off across this family, so the
# `while [ $# -gt 0 ]` loop re-read the same flag until killed. Measured as
# rc=124 under `timeout 5`. In a review chain a hung tool is strictly worse than
# a failed one: a failure is reported, a hang means the run never reports at all
# and the operator is left guessing which of nine tools stalled. Every
# value-taking flag in the family is now guarded from ONE shared helper, so the
# class is closed rather than the four instances that happened to be found.
timeout 5 sleep 10 >/dev/null 2>&1
check "POSITIVE CONTROL: timeout really reports a hang as rc=124" "[ \$? -eq 124 ]"
probe_flag() {   # probe_flag TOOL ARGS... — must exit 2 well inside the timeout
  local tool="$1"; shift
  timeout 5 "$BIN/$tool" "$@" </dev/null >/dev/null 2>&1
  local rc=$?
  check "$tool $* → usage error (2), not a hang" "[ $rc -eq 2 ]"
}
for f in --type --path --category --code --note --ledger --repo; do
  probe_flag jjstack-review-ledger "$f"
done
for f in --repo --store --key --verdict --code --lens --file --note; do
  probe_flag jjstack-review-calibration record "$f"
done
probe_flag jjstack-review-calibration validate --store
probe_flag jjstack-review-memory-migrate --repo
probe_flag jjstack-review-run-report --out
# The python rung shares the contract even though it never shared the bug — the
# guarantee is chain-wide, so the test is too.
probe_flag jjstack-review-baseline validate --baseline
probe_flag jjstack-review-baseline apply --baseline
probe_flag jjstack-review-baseline generate --reason
probe_flag jjstack-review-baseline generate --code
probe_flag jjstack-review-baseline generate -o
# POSITIVE CONTROL — the same flags WITH a value get past parsing, or "exit 2"
# above would just mean every flag is rejected unconditionally.
PB="$(mktemp -d)"
timeout 5 "$BIN/jjstack-review-memory-migrate" --repo "$PB" </dev/null >/dev/null 2>&1
check "POSITIVE CONTROL: --repo WITH a value parses and runs (exit 0)" "[ \$? -eq 0 ]"
timeout 5 "$BIN/jjstack-review-calibration" record --store "$PB/c.tsv" --key k --verdict accepted \
  </dev/null >/dev/null 2>&1
check "POSITIVE CONTROL: valued calibration flags parse and record (exit 0)" "[ \$? -eq 0 ]"
rm -rf "$PB"

echo "== 7v. THE LADDER ON EVERY RUNG, AND THE SCOPE GUARD AT EVERY ENTRY POINT =="
# Round 1 closed both of these on the baseline, because the fixture covered the
# baseline. Neither rule is a property of one script. EVERY rung has exactly one
# verb, and NO rung may hold a pattern that names no place in the repo — so both
# are asserted here on all three stores and at every entry point that reads or
# writes one: record, validate, list, match, suggest, report, generate, and the
# migration an existing user is told to run.
LX="$(mktemp -d)"
LX_HDR=$'#jjstack-review-store\tscope=path-glob\tmax-effect=demote\tv=1'
CX_HDR=$'#jjstack-review-store\tscope=pattern-class\tmax-effect=rank\tv=1'

# --- one verb per rung: the LEDGER -------------------------------------------
# `vocab_check` only ever asked whether an effect is WITHIN the ceiling, and
# `none` and `rank` both are. So a `dismissed` row spelled `none` validated `ok`
# and `--match` then printed the self-contradictory `DEMOTE effect=none` — a
# demotion announced by a row that claims to change nothing. Same class as the
# baseline's read-path hole, one rung up.
for weak in none rank; do
  { printf '%s\n' "$LX_HDR"
    printf '2026-01-01\tacme/repo\tdismissed\t%s\tprior-decision\tsrc/*\tstyle\thistory only, changes nothing\n' "$weak"; } > "$LX/w.tsv"
  for m in validate list; do
    "$BIN/jjstack-review-ledger" "--$m" --ledger "$LX/w.tsv" >/dev/null 2> "$LX/w.err"; rc=$?
    check "ledger --$m rejects a dismissed row spelled '$weak' (exit 4)" \
      "[ $rc -eq 4 ] && grep -q 'violates the ladder' '$LX/w.err'"
  done
  "$BIN/jjstack-review-ledger" --match --path src/pay.py --category style \
    --ledger "$LX/w.tsv" > "$LX/w.out" 2>/dev/null; rc=$?
  check "ledger --match rejects a dismissed row spelled '$weak' (exit 4)" "[ $rc -eq 4 ]"
  check "and never prints 'DEMOTE effect=$weak'" "! grep -q 'DEMOTE effect=$weak' '$LX/w.out'"
  "$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/other/*' --category style \
    --code prior-decision --note n --ledger "$LX/w.tsv" >/dev/null 2>&1; rc=$?
  check "ledger --record will not append to a store spelled '$weak' (exit 4)" "[ $rc -eq 4 ]"
done
# The mirror image: a HISTORY row may not carry a verdict either. `fixed` and
# `confirmed` are the record of what happened, not an instruction about what to
# do next, so a `demote` on one is a suppression wearing history's clothes.
for hist in fixed confirmed; do
  { printf '%s\n' "$LX_HDR"
    printf '2026-01-01\tacme/repo\t%s\tdemote\t-\tsrc/*\tstyle\tfixed in 12\n' "$hist"; } > "$LX/h.tsv"
  "$BIN/jjstack-review-ledger" --validate --ledger "$LX/h.tsv" >/dev/null 2>&1; rc=$?
  check "a '$hist' row carrying effect demote is rejected (exit 4)" "[ $rc -eq 4 ]"
done
# POSITIVE CONTROL — the byte-identical store spelled correctly still validates
# and still demotes, so "exit 4" above is about the effect column and not about a
# store shape the tool can no longer read at all.
{ printf '%s\n' "$LX_HDR"
  printf '2026-01-01\tacme/repo\tdismissed\tdemote\tprior-decision\tsrc/*\tstyle\thistory only, changes nothing\n'; } > "$LX/ok.tsv"
"$BIN/jjstack-review-ledger" --validate --ledger "$LX/ok.tsv" >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: the same row spelled 'demote' validates" "[ $rc -eq 0 ]"
"$BIN/jjstack-review-ledger" --match --path src/pay.py --category style \
  --ledger "$LX/ok.tsv" > "$LX/ok.out" 2>/dev/null; rc=$?
check "POSITIVE CONTROL: and it does demote" "[ $rc -eq 0 ]"
check "POSITIVE CONTROL: printing effect=demote" "grep -q 'DEMOTE effect=demote' '$LX/ok.out'"

# --- one verb per rung: CALIBRATION ------------------------------------------
# The widest rung had the same hole and hid it better: `suggest` hardcodes
# `effect=rank` into its output, so a row spelled `none` produced
# `placement=demoted effect=rank` and nothing parsing that line could see the
# mismatch. Exit 4 alone is not proof here — a missing store and "no prior data"
# also exit 4 — so every assertion names the ladder error too.
{ printf '%s\n' "$CX_HDR"
  printf '2026-01-01\ttrailing-whitespace\trejected\tnone\tprior-decision\t-\t-\thistory only\n'; } > "$LX/c.tsv"
for m in validate report; do
  "$BIN/jjstack-review-calibration" "$m" --store "$LX/c.tsv" >/dev/null 2> "$LX/c.err"; rc=$?
  check "calibration $m rejects a rejected row spelled 'none' (exit 4)" \
    "[ $rc -eq 4 ] && grep -q 'violates the ladder' '$LX/c.err'"
done
"$BIN/jjstack-review-calibration" suggest --store "$LX/c.tsv" --key trailing-whitespace \
  > "$LX/c.out" 2> "$LX/c.err"; rc=$?
check "calibration suggest rejects a rejected row spelled 'none' (exit 4)" \
  "[ $rc -eq 4 ] && grep -q 'violates the ladder' '$LX/c.err'"
check "and never reports placement=demoted from it" "! grep -q 'placement=demoted' '$LX/c.out'"
"$BIN/jjstack-review-calibration" record --store "$LX/c.tsv" --key k --verdict accepted \
  >/dev/null 2> "$LX/c.err"; rc=$?
check "calibration record will not append to a store spelled 'none' (exit 4)" \
  "[ $rc -eq 4 ] && grep -q 'violates the ladder' '$LX/c.err'"
# POSITIVE CONTROL — the byte-identical store spelled `rank` still suggests.
{ printf '%s\n' "$CX_HDR"
  printf '2026-01-01\ttrailing-whitespace\trejected\trank\tprior-decision\t-\t-\thistory only\n'; } > "$LX/cok.tsv"
"$BIN/jjstack-review-calibration" suggest --store "$LX/cok.tsv" --key trailing-whitespace \
  > "$LX/cok.out" 2>/dev/null; rc=$?
check "POSITIVE CONTROL: the same row spelled 'rank' suggests (exit 0)" "[ $rc -eq 0 ]"
check "POSITIVE CONTROL: and it does demote placement" "grep -q 'placement=demoted effect=rank' '$LX/cok.out'"

# --- the scope guard, at every entry point -----------------------------------
# PR #20 put the unscoped-glob check on `--record` and nowhere else, so
# `validate` certified a `*` row as ok and `--match` demoted every path in the
# category. A pattern built only from `*`, `?` and `/` carries no discriminating
# character: it is a blanket wherever it is written and however it got there.
for g in '*' '**' '*/*' '?' '/*'; do
  { printf '%s\n' "$LX_HDR"
    printf '2026-01-01\tacme/repo\tdismissed\tdemote\tprior-decision\t%s\tstyle\twaved off everything\n' "$g"; } > "$LX/g.tsv"
  "$BIN/jjstack-review-ledger" --validate --ledger "$LX/g.tsv" >/dev/null 2> "$LX/g.err"; rc=$?
  check "ledger --validate rejects the blanket glob '$g' (exit 4)" \
    "[ $rc -eq 4 ] && grep -q 'matches every file' '$LX/g.err'"
  "$BIN/jjstack-review-ledger" --match --path src/payments.py --category style \
    --ledger "$LX/g.tsv" > "$LX/g.out" 2>/dev/null; rc=$?
  check "ledger --match will not demote from '$g' (exit 4)" "[ $rc -eq 4 ]"
  check "and prints no DEMOTE line for '$g'" "! grep -q DEMOTE '$LX/g.out'"
  "$BIN/jjstack-review-ledger" --list --ledger "$LX/g.tsv" > "$LX/g.list" 2>/dev/null; rc=$?
  check "ledger --list will not print '$g' as if it were a decision (exit 4)" "[ $rc -eq 4 ]"
  check "and lists nothing from it" "[ ! -s '$LX/g.list' ]"
done
# The baseline's own version of the guard stripped `*` and `?` but not `/`, so
# `*/*` — which matches every nested path there is — walked past it. Same class,
# same file, one rung down.
for g in '*/*' '**' '*?'; do
  { printf '%s\n' "$BL_HDR"
    printf 'rule\tsuppress\tbaseline\t-\t-\t%s\t-\tdead code path\n' "$g"; } > "$LX/b.tsv"
  "$BIN/jjstack-review-baseline" validate --baseline "$LX/b.tsv" >/dev/null 2>&1; rc=$?
  check "baseline rejects the blanket file glob '$g' (exit 4)" "[ $rc -eq 4 ]"
done
# POSITIVE CONTROL — a WIDE but real glob is still a decision about a place, and
# it still validates on both rungs. `src/*` above already demoted; `per*` here is
# the shipped spelling from the baseline's own ceiling fixture.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\tbaseline\t-\tper*\t-\t-\tdead code\n'; } > "$LX/bok.tsv"
"$BIN/jjstack-review-baseline" validate --baseline "$LX/bok.tsv" >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: a wide glob that names something still validates" "[ $rc -eq 0 ]"

# --- the upgrade path may not launder what the stores refuse ------------------
# `jjstack-review-memory-migrate` is the one command every existing user is told
# to run, and it printed "delete the legacy ones" the moment it finished. A
# legacy row carrying a blanket glob migrated straight through, validated ok, and
# demoted the repo — a second, sanctioned way for a `*` row to exist. Migration
# is not an exemption from the ladder; it is where the ladder matters most. So
# migrate now runs each converted store through the validator of the tool that
# OWNS it, and installs only what passes.
MX="$(mktemp -d)"; mkdir -p "$MX/jjstack"
printf '2026-01-01 | acme/repo | dismissed | * | style | waved off everything\n' > "$MX/jjstack/review-ledger.md"
"$BIN/jjstack-review-memory-migrate" --repo "$MX" > "$MX/out" 2> "$MX/err"; rc=$?
check "migrate refuses a legacy blanket glob (non-zero)" "[ $rc -ne 0 ]"
check "and installs no store its own validator would reject" \
  "[ ! -f '$MX/jjstack/review-memory/ledger.tsv' ]"
check "and quotes the validator's reason" "grep -q 'matches every file' '$MX/err'"
check "and does NOT then tell you to delete the legacy file" "! grep -q 'delete the legacy' '$MX/out'"
check "and leaves the rejected conversion to be read" \
  "[ -f '$MX/jjstack/review-memory/ledger.tsv.rejected' ]"
# The same net, one rung down: a legacy JSON rule the baseline would reject.
MX3="$(mktemp -d)"
printf '{"jjstack_version":"1.0.0","rules":[{"path":"*","message":"","reason":"waved off"}],"fingerprints":[]}\n' > "$MX3/.jjstack-review-baseline.json"
"$BIN/jjstack-review-memory-migrate" --repo "$MX3" >/dev/null 2> "$MX3/err"; rc=$?
check "migrate refuses a legacy JSON rule the baseline would reject (non-zero)" "[ $rc -ne 0 ]"
check "and installs no baseline" "[ ! -f '$MX3/jjstack/review-memory/baseline.tsv' ]"
# A legacy Markdown note is free text a human typed, and `|` is ordinary in
# English prose. Splitting on every pipe truncated the note at the first one and
# then told the reader to delete the original — the reason for a live suppression
# silently discarded on the upgrade path.
MX2="$(mktemp -d)"; mkdir -p "$MX2/jjstack"
printf '2026-01-02 | org/repo | dismissed | src/vendor/* | style | vendored code | see ADR-7 for why\n' > "$MX2/jjstack/review-ledger.md"
"$BIN/jjstack-review-memory-migrate" --repo "$MX2" >/dev/null 2>&1; rc=$?
check "a clean legacy ledger still migrates (exit 0)" "[ $rc -eq 0 ]"
check "a legacy note containing a pipe survives migration whole" \
  "grep -q 'see ADR-7 for why' '$MX2/jjstack/review-memory/ledger.tsv'"
check "and stays inside the note column, not a ninth field" \
  "awk -F'\t' '/^2026-/{ exit !(NF == 8 && \$8 ~ /vendored code/ && \$8 ~ /ADR-7/) }' '$MX2/jjstack/review-memory/ledger.tsv'"
"$BIN/jjstack-review-ledger" --validate --ledger "$MX2/jjstack/review-memory/ledger.tsv" >/dev/null 2>&1
check "POSITIVE CONTROL: and what migrate installed validates" "[ \$? -eq 0 ]"
rm -rf "$MX" "$MX2" "$MX3"

# --- `generate` is an entry point too ----------------------------------------
# The legacy-JSON guard lives in load_store's NOT-EXISTS branch, which is exactly
# the branch `generate` skips: with no new store yet and a legacy JSON beside it,
# generate wrote a fresh baseline and silently abandoned every human-written rule
# in the file it never read.
GX="$(mktemp -d)"
printf '{"jjstack_version":"0.9.0","rules":[{"path":"src/legacy/*","reason":"agreed exception"}],"fingerprints":[]}\n' > "$GX/.jjstack-review-baseline.json"
printf '{"lens":"sec","file":"src/a.py","message":"boom","severity":"P0"}\n' > "$GX/f.jsonl"
( cd "$GX" && "$BIN/jjstack-review-baseline" generate f.jsonl --reason r \
    -o jjstack/review-memory/baseline.tsv ) >/dev/null 2> "$GX/err"; rc=$?
check "generate stops on an un-migrated legacy JSON baseline (exit 3)" "[ $rc -eq 3 ]"
check "and names the migrate command" "grep -q 'jjstack-review-memory-migrate' '$GX/err'"
check "and writes nothing beside the store it never read" \
  "[ ! -f '$GX/jjstack/review-memory/baseline.tsv' ]"
# POSITIVE CONTROL — with the legacy file gone the same command writes a store,
# so "exit 3" measures the guard and not a broken generate.
rm -f "$GX/.jjstack-review-baseline.json"
( cd "$GX" && "$BIN/jjstack-review-baseline" generate f.jsonl --reason r \
    -o jjstack/review-memory/baseline.tsv ) >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: without the legacy file the same command writes one" \
  "[ $rc -eq 0 ] && [ -f '$GX/jjstack/review-memory/baseline.tsv' ]"

# `--replace` skipped load_store, and load_store is where the cross-rung check
# lives — so the very flag the refusal message recommends ("pass --replace to
# start fresh") converted a ledger into an empty baseline. Another rung's file is
# never ours to start fresh in, with or without the flag.
VX="$(mktemp -d)"
{ printf '%s\n' "$LX_HDR"
  printf '2026-01-01\tacme/repo\tdismissed\tdemote\tprior-decision\tsrc/legacy/*\tstyle\tagreed\n'; } > "$VX/ledger.tsv"
cp "$VX/ledger.tsv" "$VX/before.tsv"
printf '{"lens":"sec","file":"src/a.py","message":"boom","severity":"P0"}\n' > "$VX/f.jsonl"
"$BIN/jjstack-review-baseline" generate "$VX/f.jsonl" --reason r -o "$VX/ledger.tsv" --replace \
  >/dev/null 2> "$VX/err"; rc=$?
check "generate --replace still refuses another rung's store (exit 4)" "[ $rc -eq 4 ]"
check "and the ledger is byte-identical afterwards" "cmp -s '$VX/ledger.tsv' '$VX/before.tsv'"
check "and the refusal does not recommend --replace as the way out" \
  "! grep -q 'pass --replace' '$VX/err'"
# POSITIVE CONTROL — `--replace` still does the job it exists for: a store of OUR
# OWN rung that will not load is exactly the case it is documented for.
{ printf '%s\n' "$BL_HDR"
  printf 'rule\tsuppress\tbaseline\t-\t-\t-\t-\t-\n'; } > "$VX/own.tsv"
"$BIN/jjstack-review-baseline" validate --baseline "$VX/own.tsv" >/dev/null 2>&1
check "POSITIVE CONTROL: the own-rung store really is broken" "[ \$? -ne 0 ]"
"$BIN/jjstack-review-baseline" generate "$VX/f.jsonl" --reason r -o "$VX/own.tsv" --replace \
  >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: --replace still starts fresh on our own broken store" "[ $rc -eq 0 ]"

# --- `stale-api` is earned at review time, never remembered -------------------
# The merge-added code declares a `suppress` ceiling, so its exclusive binding to
# `refuted` was enforced only by run-report's Invariant 4. In the three memory
# stores it was an ordinary full-strength suppression code: `generate --code
# stale-api` retired a P0 with no doc URL and nothing having consulted any
# documentation. A stale-API refutation is external evidence produced by §4.5b of
# a particular run; it is not something a store may hold, so its ceiling is now
# `none` and every store rejects it by the same arithmetic as every other code.
SX="$(mktemp -d)"
printf '{"lens":"sec","file":"src/x.py","message":"P0 sql injection","severity":"P0"}\n' > "$SX/p0.jsonl"
"$BIN/jjstack-review-baseline" generate "$SX/p0.jsonl" --reason "docs say otherwise" \
  --code stale-api -o "$SX/b.tsv" >/dev/null 2>&1; rc=$?
check "the baseline refuses to suppress with stale-api (exit 4)" "[ $rc -eq 4 ]"
check "and writes no store" "[ ! -f '$SX/b.tsv' ]"
"$BIN/jjstack-review-ledger" --record --type dismissed --path 'src/*' --category style \
  --code stale-api --note n --ledger "$SX/l.tsv" >/dev/null 2>&1; rc=$?
check "the ledger refuses to demote with stale-api (exit 4)" "[ $rc -eq 4 ]"
check "and writes no store" "[ ! -f '$SX/l.tsv' ]"
"$BIN/jjstack-review-calibration" record --store "$SX/c.tsv" --key k --verdict rejected \
  --code stale-api >/dev/null 2>&1; rc=$?
check "calibration refuses to rank with stale-api (exit 4)" "[ $rc -eq 4 ]"
check "and writes no store" "[ ! -f '$SX/c.tsv' ]"
# A hand-edited store may not smuggle it in either — the read path is the other
# half of every one of these guards.
{ printf '%s\n' "$LX_HDR"
  printf '2026-01-01\tacme/repo\tdismissed\tdemote\tstale-api\tsrc/*\tstyle\tdocs say otherwise\n'; } > "$SX/hand.tsv"
"$BIN/jjstack-review-ledger" --validate --ledger "$SX/hand.tsv" >/dev/null 2>&1; rc=$?
check "a hand-written stale-api ledger row is rejected on read (exit 4)" "[ $rc -eq 4 ]"
# POSITIVE CONTROL — the run report, where the code IS earned and IS paired with
# `refuted`, still takes it. Recovered verbatim from the shipped §7d fixture.
row P1 85 src/e.py:1 stale-api refuted stale-api 'API changed in 2.0; code is correct per current docs (https://example/docs)' > "$SX/ref.tsv"
"$BIN/jjstack-review-run-report" "$SX/ref.tsv" --out "$SX/ref.md" >/dev/null 2>&1; rc=$?
check "POSITIVE CONTROL: refuted + stale-api is still legal in the run report" "[ $rc -eq 0 ]"
check "POSITIVE CONTROL: and it still renders as refuted" "grep -q 'Refuted' '$SX/ref.md'"
rm -rf "$LX" "$GX" "$VX" "$SX"

echo "== 6. hermeticity guard (this file lints itself) =="
# Hermeticity that lives only in the fixtures decays the moment someone adds an
# assertion without one — which is exactly what happened here: the fixture built
# for the write assertion in section 4 was not carried up to the Layer-B block
# twenty lines above it, and the suite stayed green while reading the
# developer's real memory store. The sandbox above makes the DEFAULT hermetic;
# this lint makes the remaining escape hatches LOUD.
#
# Three ways an assertion reaches back out of the sandbox, all of them one grep
# away:
#   a --cwd aimed at $DIR   points a memory tool at the live checkout: its git
#                           remote, its real slug resolution, and the memory
#                           dir keyed to this repo
#   /home/<user>            a hardcoded developer path
#   -home-<user>            the dashed form of one, which is how the native
#                           memory dirs and the PHI slugs are keyed
# A line may opt out with the marker the lint's own filter names; the count of
# opted-out lines is pinned below, so a new exemption cannot slip in silently.
hermetic_lint() {   # hermetic_lint <file> → one line per escape hatch
  grep -nE -e '--cwd[[:space:]]+"[$]DIR"' -e '/home/[a-z]' -e '-home-[a-z]' "$1" \
    | grep -v 'hermetic-ok'
}
viol=$(hermetic_lint "$SELF")
[ -n "$viol" ] && printf '     %s\n' "$viol"
check "no assertion reaches outside the sandbox" "[ -z \"\$viol\" ]"

# POSITIVE CONTROL. A lint that has never flagged anything is indistinguishable
# from a lint whose pattern is wrong, and the assertion above passes either way.
# The specimen is not invented: it is byte-for-byte the line this PR removed,
# recovered from git at 74e87e7:test/smoke.sh:60 — the Layer-B invocation that
# ran against the live repo while the suite reported 40/40.
CTL='out=$(JJSTACK_CAPTURE_NO_GBRAIN=1 "$BIN/jjstack-capture-write" --cwd "$DIR" --dry-run --lesson "$LESSON" 2>&1)'  # hermetic-ok: git-recovered specimen, fed to the lint on purpose
CTLF="$SANDBOX/lint-specimen.sh"; printf '%s\n' "$CTL" > "$CTLF"
check "the lint flags the exact line this PR removed (control)" "[ \"\$(hermetic_lint '$CTLF' | wc -l)\" = 1 ]"
# And the exemption marker must stay rare enough to read at a glance.
exempt=$(grep -c 'hermetic-ok' "$SELF")
check "the lint has exactly 3 opted-out lines (adding one reddens this)" "[ \"\$exempt\" = 3 ]"

# Runtime half of the guard: the sandbox must still be in force at the end. A
# section that reassigns $HOME and forgets to restore it would leave every later
# assertion pointed at the real store, silently.
check "the sandbox \$HOME survived the whole run" "[ \"\${HOME#\$SANDBOX}\" != \"\$HOME\" ]"

echo "== 8. the runner's own assertion semantics =="
# check() suspends pipefail for the duration of an assertion. That is only safe
# if two things still hold, so both are asserted here rather than assumed.
#
# 1. A pipeline assertion that genuinely does not match must still FAIL. If it
#    did not, suspending pipefail would have turned 206 pipeline assertions in
#    this file into unconditional passes.
runner_pass=0; runner_fail=0
runner_probe() { if eval "$1"; then runner_pass=$((runner_pass+1)); else runner_fail=$((runner_fail+1)); fi; }
set +o pipefail
runner_probe "printf 'alpha\n' | grep -q 'alpha'"
runner_probe "printf 'alpha\n' | grep -q 'omega'"
set -o pipefail
check "with pipefail off a matching pipeline assertion still passes" "[ $runner_pass -eq 1 ]"
check "with pipefail off a NON-matching pipeline assertion still fails" "[ $runner_fail -eq 1 ]"
# 2. `$?` must survive into the assertion. `set` resets it, and dozens of checks
#    in this file are written as `[ $? -eq 2 ]` against the preceding command —
#    silently reading 0 instead would turn every exit-code check green.
( exit 7 )
check "\$? reaches the assertion intact across check()'s own set" "[ \$? -eq 7 ]"
# POSITIVE CONTROL — and it must not be pinned to some constant either.
( exit 3 )
check "positive control: a different exit code reaches it too" "[ \$? -eq 3 ]"

echo "== 9. this file's own section labels =="
# Three round-1 sections were appended with labels 7e/7f/7g that already belonged
# to three later sections in the same file. Nothing broke, but a 400+ check run
# whose section headings repeat cannot be navigated: "7f failed" names two
# places. The guard is over the whole label space, not over the three that
# collided, so the next appended section is caught the same way.
dup_labels=$(grep -oE '^echo "== [0-9]+[a-z]*\.' "$0" | sort | uniq -d)
check "no two sections share a label${dup_labels:+ — duplicated: $(printf '%s' "$dup_labels" | tr '\n' ' ')}" \
  "[ -z \"\$dup_labels\" ]"
# POSITIVE CONTROL — the detector must be able to SEE a duplicate, or "none
# found" would only mean the expression matches nothing at all.
check "positive control: the label detector finds a planted duplicate" \
  "[ \"\$(printf 'echo \"== 7f. a =\"\necho \"== 7f. b =\"\necho \"== 7z. c =\"\n' | grep -oE '^echo \"== [0-9]+[a-z]*\\.' | sort | uniq -d | wc -l | tr -d ' ')\" = 1 ]"
# POSITIVE CONTROL — and it must really be reading this file's labels, not an
# empty set: this run has more than a dozen of them.
check "positive control: the detector reads this file's real labels" \
  "[ \"\$(grep -cE '^echo \"== [0-9]+[a-z]*\\.' '$0')\" -ge 15 ]"


echo
if [ "$fail" -eq 0 ]; then printf '\033[92mALL %d PASS\033[0m\n' "$pass"; exit 0
else printf '\033[95m%d FAIL\033[0m, %d pass\n' "$fail" "$pass"; exit 1; fi
