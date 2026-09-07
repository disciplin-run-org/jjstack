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
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

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
         "$BIN"/jjstack-review-calibration "$BIN"/jjstack-review-triage \
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

echo "== 5g. review-baseline (suppression, never deletion) =="
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
# PR #16 review ROUND 2 (P1): the round-1 guard checked the five keys
# INDEPENDENTLY, but `rule_matches` resolves them as ALIAS PAIRS — `id or
# rule_id`, `path or file`, first truthy wins. So a discriminating value in the
# LOSING alias made the rule look scoped while `*` was still the pattern
# actually applied. Reproduced: {"id":"*","rule_id":"security"} → 0 active,
# 2 suppressed, rc=0 — the whole repo muted at a clean exit.
# `id` beats `rule_id` and `path` beats `file`, so only those two directions
# can hide a wildcard; the mirrored pair is asserted below as INERT.
for pair in 'id:rule_id' 'path:file'; do
  wild="${pair%%:*}"; loser="${pair##*:}"
  printf '{"version":2,"jjstack_version":"x","rules":[{"%s":"*","%s":"scoped","reason":"noisy"}],"fingerprints":[]}\n' \
    "$wild" "$loser" > "$RB/alias.json"
  "$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/alias.json" \
    > "$RB/alias.out" 2>/dev/null; rc=$?
  check "wildcard $wild beside a scoped $loser exits 2" \
    "[ $rc -eq 2 ] && [ ! -s '$RB/alias.out' ]"
  "$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" \
    --baseline "$RB/alias.json" > "$RB/alias.err" 2>&1
  check "the rejection says the losing $loser never applies" \
    "grep -q '$loser never applies' '$RB/alias.err'"
done
# Positive control — the guard must reject the alias that WINS, not alias pairs
# as such. With the discriminating value in the winning slot the rule is
# legitimate, the `*` in the losing slot is inert, and suppression must still
# be exactly as narrow as the winning pattern says. This is also what pins WHICH
# alias wins: swap the precedence in either place and these go red.
printf '{"version":2,"jjstack_version":"x","rules":[{"id":"sec*","rule_id":"*","reason":"policy: security lens is advisory here"}],"fingerprints":[]}\n' \
  > "$RB/aliasok.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/aliasok.json" \
  --active-only > "$RB/aliasok.out" 2>/dev/null; rc=$?
check "positive control: a scoped winning id makes rule_id:* inert" \
  "[ $rc -eq 1 ] && [ \"\$(wc -l < '$RB/aliasok.out')\" -eq 1 ]"
check "positive control: it suppressed only the security lens" \
  "grep -q 'n+1 query' '$RB/aliasok.out'"
printf '{"version":2,"jjstack_version":"x","rules":[{"path":"b*","file":"*","reason":"policy: b.py is vendored"}],"fingerprints":[]}\n' \
  > "$RB/aliasok2.json"
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/aliasok2.json" \
  --active-only > "$RB/aliasok2.out" 2>/dev/null; rc=$?
check "positive control: a scoped winning path makes file:* inert" \
  "[ $rc -eq 1 ] && [ \"\$(wc -l < '$RB/aliasok2.out')\" -eq 1 ]"
check "positive control: it suppressed only b.py" \
  "grep -q 'shell injection' '$RB/aliasok2.out'"
# The annotation must show the pattern that was APPLIED. Printing every key
# present made a losing alias read to a human as a scoped rule.
"$BIN/jjstack-review-baseline" apply "$RB/findings.jsonl" --baseline "$RB/aliasok.json" \
  > "$RB/aliasann.out" 2>/dev/null
check "the suppression annotation shows only the winning alias" \
  "grep -q 'sec\*' '$RB/aliasann.out' && ! grep -q 'rule_id' '$RB/aliasann.out'"

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
# ...but that path returns 2 at LOAD time, before any temp file is created, so
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
# names the .tmp as the rename source. (Literals recovered from
# bin/jjstack-review-baseline and from the OS, not invented for this test.)
check "positive control: it failed at the RENAME, not the load" \
  "grep -q 'cannot write' '$RB/adir.err' && grep -q 'adir.tmp' '$RB/adir.err'"
check "positive control: the directory it refused to clobber is intact" \
  "[ -f '$RB/adir/keep' ]"
rm -rf "$RB/adir" "$RB/adir.err"
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
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "tabby" --verdict accepted --note "a	b	c" >/dev/null 2>&1
# Field-count integrity: a tab in free text would shift every column after it.
# The old form, `awk -F'\t' '/tabby/{exit !(NF==6)}'`, exits 0 when NO line
# matches — so it passed just as happily when the row was missing entirely.
# Assert the row EXISTS and is well formed, and prove the assertion can fail.
row_is_intact() { # row_is_intact <ledger> <key>
  awk -F'\t' -v k="$2" '$2 == k { seen = 1; if (NF != 6) bad = 1 }
                        END { exit (seen && !bad) ? 0 : 1 }' "$1"
}
check "tabs in --note cannot corrupt the row" "row_is_intact '$LEDGER' tabby"
check "control: the row check fails when the row is absent" \
  "! row_is_intact '$LEDGER' definitely-never-recorded"
before=$(wc -l < "$LEDGER")
"$BIN/jjstack-review-calibration" record --store "$LEDGER" --key "dry" --verdict accepted --dry-run >/dev/null 2>&1
check "--dry-run appends nothing" "[ \$(wc -l < '$LEDGER') -eq $before ]"
# Ordering IS the product of `report` — it is the ranked view of the ledger.
# `%+6d` emits "+20", and `sort -n` cannot parse a leading '+', so the sort key
# collapsed to 0 and the ranked output came back unranked. The keys below are
# chosen so alphabetical order is NOT rank order; otherwise a broken sort could
# come out right by coincidence.
ORD="$CAL/ordering.tsv"
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "aaa-top" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "aaa-top" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "bbb-mid" --verdict accepted >/dev/null 2>&1
"$BIN/jjstack-review-calibration" record --store "$ORD" --key "ccc-low" --verdict rejected >/dev/null 2>&1
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
# appendix item, one suppressed nit, one deferred vendor finding.
{
  row P1 80 src/auth.py:42      security    report   -              'missing authz check on admin route'
  row P1 72 src/auth.py:42      correctness report   -              'Missing authz check on admin route!'
  row P2 55 src/util.py:9       perf        appendix low-confidence 'N+1 query in loop'
  row P3 30 tests/test_x.py:5   style       suppress style-only     'trailing whitespace'
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
check "suppressed finding records its reason"   "grep -q 'style-only' '$TRI/good.md'"

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
check "not-reachable error offers defer/appendix instead"        "grep -q 'deprioritise' '$TRI/reach.err'"

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
rm -rf "$TRI"

echo "== 7d. value-less flags must be a usage error, never a hang =="
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

echo "== 7e. --help is derived from the header, not a hand-kept line range =="
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

echo "== 7f. review-sweep PARTIAL: a check set with no test runner is not clean =="
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

echo "== 7f2. the sweep must read package.json as data, never as code =="
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

echo "== 7g. the docs must not teach the deleted rescoring/deletion model =="
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

echo "== 7h. --mark is actually invoked, not just implemented =="
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

echo
if [ "$fail" -eq 0 ]; then printf '\033[92mALL %d PASS\033[0m\n' "$pass"; exit 0
else printf '\033[95m%d FAIL\033[0m, %d pass\n' "$fail" "$pass"; exit 1; fi
