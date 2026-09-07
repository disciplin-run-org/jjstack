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
         "$BIN"/jjstack-capture-review-refs \
         "$BIN"/jjstack-review-preflight "$BIN"/jjstack-review-tooling-sweep \
         "$BIN"/jjstack-review-blast-radius "$BIN"/jjstack-review-intent \
         "$BIN"/jjstack-review-prior-dismissals \
         "$HOOKS"/shared-memory.sh "$HOOKS"/capture-on-end.sh; do
  check "bash -n $(basename "$f")" "bash -n '$f' 2>/dev/null"
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
rm -rf "$PF"

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
