---
name: review
version: 1.1.0
description: |
  The deepest, highest-recall pre-landing review in the stack. Wraps gstack's
  /review but deliberately trades time and tokens for COVERAGE: it opens with a
  deterministic pre-flight evidence pack (runs the real typechecker/linter/tests,
  maps every changed public symbol's callers outside the diff, gathers the
  change's stated intent, loads previously dismissed findings, snapshots the test
  baseline), forces every
  specialist to run (no adaptive gating, no small-diff skip), adds the review
  passes that Anthropic's /code-review and gstack both skip (security, test
  coverage, performance, concurrency, resource leaks, error handling, API
  misuse, git-history context, prior-PR comments, code-comment + CLAUDE.md
  compliance), then controls the resulting noise with an enrich-only
  verification pass and a committed baseline — never by deleting findings.
  Then it runs five post-passes no diff-reader can do: what SHOULD have changed
  and didn't, a review of the fixes the reviewer auto-applied, a red test
  proving each finding, a re-run of the project's typechecker/linter/tests on
  the post-fix tree, and persisted accept/reject calibration that ranks the next
  review without ever rescoring a finding. Emits a three-valued
  APPROVE/CAUTION/REJECT verdict with per-finding review judgments and
  guardrails. Saves findings to {repo}/jjstack/, injects DNA, iterates to 10/10.
  Use on the diff about to merge when you want to catch what a fast review
  would miss.
  Trigger on: "review my changes", "pre-landing review", "review the diff",
  "review before merge", "deep review", "adversarial review", "review this PR",
  "catch everything review", "thorough review".
  Do NOT trigger for: a fast/cheap pass (use gstack /review or the code-review
  plugin directly), a specific PR by number for a quick comment (use
  /smart-review or the code-review plugin), security-only review
  (use /security-review), two-stage spec-then-quality review
  (use /two-stage-review), processing incoming review feedback
  (use /receiving-code-review), or design/UI review (use /design-review).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - WebSearch
  - Agent
  - Edit
  - Write
---

# jjstack review wrapper — recall-max, self-verified

This skill wraps gstack's `/review` with jjstack's philosophy AND a deliberate
bias toward **catching more**. Fast reviewers (Anthropic's `/code-review`,
gstack's default `/review`) are tuned for efficiency: they gate specialists,
skip small diffs, and drop whole dimensions (security, test coverage, general
quality) to stay low-noise. This skill inverts that trade — it runs **every**
lens and then earns its low noise back through per-finding verification.

**Design provenance:** the multi-agent fan-out and the git-history / prior-PR /
code-comment / CLAUDE.md-compliance passes are drawn from Anthropic's official
`/code-review` command, folded on top of gstack's Review Army. The verification
architecture — enrich-only, fail-closed, a committed baseline instead of
deletion, line-numbered grounding, and the three-valued verdict — is drawn from
NVIDIA's `SkillSpector`. The best practices behind the extra passes and the
noise-control are documented (with sources) in
`references/code-review-best-practices.md`, loaded in Phase 3. Phase 0 is the
jjstack-original half: it applies the "Algorithm First, Inference Last" rule to
review — run the compiler, grep the callers, read the commit message — so no
token of judgement is spent on a fact. Its reasoning lives in
`references/review-preflight.md`, loaded in Phase 0.

Six enhancements over the gstack base:
1. **Pre-flight evidence pack** — five deterministic pre-passes run BEFORE any
   AI pass: run the real tooling, map the diff's blast radius outside itself,
   gather the change's stated intent, load prior dismissals, snapshot the test
   baseline. Nothing here costs a token of judgement.
2. **Recall-max delegation** — force all specialists, disable adaptive gating
   and the small-diff skip, run extra adversarial passes.
3. **Superset dimension sweep** — add the passes gstack + Anthropic skip.
4. **Enrich-only verification** — every finding carries a quote, a concrete
   failure scenario, a remediation, and a review judgment. Verification may
   enrich a finding or mark it unconfirmed; it may never delete one. Noise is
   controlled by a committed baseline with a stated reason, not by deletion.
5. **Post-passes (5.6–5.10)** — the five things a finished review still hasn't
   done: look for what's *missing* from the diff, review the fixes the reviewer
   itself auto-applied, prove each finding with a red test, re-run the
   deterministic checks on the post-fix tree, and persist accept/reject verdicts
   that RANK the next review without ever rescoring a finding. Manual:
   `references/review-post-passes.md`.
6. **jjstack finish** — repo-local output, DNA injection, quality loop to 10/10,
   README maintenance.

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

---

## Phase 1: Configure

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store: `MIN_SCORE`, `MAX_ITERATIONS`, `ADVERSARIAL_PASSES`, `OUTPUT_DIR`, DNA paths.

```bash
mkdir -p {OUTPUT_DIR}
```

Load DNA files if configured.

---

## Phase 0: Pre-flight evidence pack (runs BEFORE the AI review)

*Numbered 0 because it precedes every reviewing phase; it is written after
Phase 1 only because it needs `{OUTPUT_DIR}` to exist.*

Deterministic evidence first. An AI pass that has to *infer* what a compiler
already knows, what the change claims, or what the user already rejected is
spending judgement on facts — and it will be worse at it. Build the pack, then
review.

```bash
cat ~/.claude/skills/jjstack/references/review-preflight.md
```

That reference is the operating manual for this phase: what each pre-pass
gathers, the reasoning for it, and how the later phases must consume it. Read
it before running the command below.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-preflight --out {OUTPUT_DIR}/preflight
```

One command runs all five pre-passes and writes `EVIDENCE-PACK.md` plus the
artifacts. This is the **only** blast-radius run in the whole review (Module
G.1); if the diff touches a shared module whose consumers live in a sibling repo,
add `--also-repo <path>` here, once per sibling, rather than scanning again
later. Then read the pack:

```bash
cat {OUTPUT_DIR}/preflight/EVIDENCE-PACK.md
```

```bash
cat {OUTPUT_DIR}/preflight/intent.md {OUTPUT_DIR}/preflight/exclusions.md {OUTPUT_DIR}/preflight/blast-radius.md {OUTPUT_DIR}/preflight/prior-dismissals.md {OUTPUT_DIR}/preflight/tooling-results.md
```

Then, before anything else, do the one judgement-shaped part of Phase 0
(pre-pass 3, intent):

> **Restate, in one or two sentences, what this change claims to do** — drawn
> from `intent.md`, not from the diff. Write it down. Every later pass compares
> the code against this restatement. If `intent.md` recovered no claim, say
> "no stated intent was recoverable" and carry that into the report; do not
> invent a claim and grade the code against your own invention.

Pass options worth knowing: `--base REF` to review against a specific base,
`--skip-tests` when the suite is too slow to sit through, `--dry-run` to see
what would run. A pre-pass reported as *skipped — structurally inapplicable*
(no test runner, no PR, no review history) is a legitimate outcome: carry it
into the report as a **known gap**, never let its absence read as a pass.

Read the index rows literally — they are rendered from per-tool facts, so they
distinguish states a summary would blur. Three of them are gaps, not passes:
*COULD NOT RUN* (the tool never judged the code), *NO baseline exists* (nothing
recorded, so no later pass may claim the change broke nothing), and *NOTHING was
checked* (no tooling detected at all). Each belongs in the report as a stated
limit of this review.

Phase 0 **executes the reviewed repo's own tooling** — its `npm run` scripts,
`make` targets, `test/smoke.sh`. That is the point on a tree you trust, and it
is not appropriate on one you do not. To review without executing anything, add
`--typecheck none --lint none --test none` to the same
`jjstack-review-preflight` command above — the flags pass straight through to
the sweep — and note in the report that all three categories are IN SCOPE.

`--base` must name a ref this repo can resolve. A typo is refused with a named
error before any pass runs, rather than producing an evidence pack full of empty
artifacts that read like clean results.

---

## Phase 2: Delegate to gstack — recall-max

**First, mark the auto-fix baseline. This is not optional and it cannot be done
later.** gstack's Step 5b auto-applies fixes; Phase 5.7 reviews that diff, and
the marker is the only thing separating the reviewer's edits from the user's own
uncommitted work. Take it now, before gstack can write anything:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-autofix-diff --mark
```

Without it, 5.7 falls back to `HEAD` and diffs the entire dirty tree — reporting
the user's own work-in-progress back to them as P1 findings written by an
automaton. Exit 3 (not a git repo, or no commits) means 5.7 is structurally
inapplicable: note it here and report 5.7 as skipped with that reason.

```bash
cat ~/.claude/skills/gstack/review/SKILL.md
```

Follow ALL of gstack's instructions, with these jjstack overrides that bias the
review toward coverage over speed:

- **Output path override:** `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`.
- **Run every specialist.** When you reach gstack's Review Army dispatch
  (`sections/review-army.md`), treat it as if the user passed
  `--all-specialists`: dispatch Testing, Maintainability, Security, Performance,
  Data Migration, API Contract, Design, and Simplification **regardless of scope
  gating, adaptive hit-rate gating, or the DIFF_LINES thresholds.** The
  small-diff skip (`DIFF_LINES < 50`) and the auto-gate ("0 findings in N
  reviews") are efficiency optimizations — they are exactly what this skill is
  built to override. A small diff can still hide a P0.
- **Extra adversarial passes.** After gstack's critical pass, run
  `ADVERSARIAL_PASSES` additional rounds (default 2; gstack default 1). Each
  round re-reads the diff assuming the previous round missed something and looks
  from a fresh attacker/maintainer angle.
- **Keep gstack's pre-emit verification gate** (quote the motivating line) — it
  is not overridden; it is the floor that Phase 5 builds on.
- **Hand every specialist the Phase 0 evidence pack.** In each dispatch include,
  verbatim: the intent restatement, the `exclusions.md` COVERED/IN SCOPE lists,
  the `blast-radius.md` symbol→call-site map, and the `prior-dismissals.md`
  fingerprints. A specialist that does not receive them will rediscover
  (expensively) or miss (silently) exactly what Phase 0 already established.
- **Fold `tooling-results.md` failures straight into the findings** — they are
  facts from a compiler or test runner, not claims. They skip Phase 5 scoring.
  This applies **only** to the `… FAILED — real findings` sections. A
  `… COULD NOT RUN — a KNOWN GAP, NOT a finding` section is the opposite: the
  tool never judged the code, so nothing in it may be reported as a finding.
  Carry it as a gap and leave that category IN SCOPE.
- **When gstack auto-applies a fix, re-check it against `test-baseline.md`**
  before accepting it. An auto-fix that turns a green baseline red is a P0.
  First check that a baseline *exists*: if `EVIDENCE-PACK.md` row 5 says
  **NO baseline exists**, there is nothing to compare against — say so, and do
  not let an auto-fix through on an unmade comparison.

---

## Phase 3: Load AI code-review best practices

```bash
cat ~/.claude/skills/jjstack/references/code-review-best-practices.md
```

Apply that reference as the operating manual for the rest of this skill: it
carries the dimension checklist, the noise-control rules, the failure-scenario
requirement, and the anti-patterns to avoid, each with its source.

---

## Phase 4: Superset dimension sweep (the passes others skip)

gstack's Review Army covers Testing / Maintainability / Security / Performance /
Data Migration / API Contract / Design / Simplification. Anthropic's
`/code-review` adds four context passes that gstack does not, and deliberately
drops security + test-coverage + quality. This phase runs the **union** — the
context passes AND the dropped dimensions — as independent parallel agents so
each reviews with a clean, single-lens context window.

**Launch all applicable passes in ONE message (multiple Agent calls) so they run
concurrently.** Each agent returns findings in the struct Phase 5b defines
(lens, file, start_line, severity, confidence, message, quote, explanation,
remediation) — and per Phase 5a it must be fed line-numbered content, so those
line numbers are copied rather than counted. Skip a pass only when it is
structurally inapplicable (e.g. no prior PRs on a brand-new repo), never merely
to save tokens — and when you skip one, record it for the degraded-mode section
in 5f.

**Every Phase 4 agent prompt MUST carry the Phase 0 evidence pack inline** —
sub-agents start with an empty context window, so an artifact they were not
handed does not exist for them. Include in each dispatch:

- the **intent restatement** — the claim the pass judges the code against;
- `exclusions.md` — "do NOT report the COVERED categories; the IN SCOPE ones
  are yours and got no free pass";
- `blast-radius.md` — "these call sites are outside the diff; verify each one
  still holds against the new definition";
- `prior-dismissals.md` — "do not regenerate these fingerprints, unless this
  diff materially changed the code they point at (then say so explicitly)."

Context passes (from Anthropic's `/code-review`, adapted from PR to local diff):

1. **Git-history pass** — for each hunk in the diff, read `git log -p` / `git
   blame` on the surrounding lines. Flag changes that reintroduce a
   previously-fixed bug, contradict the intent of a recent commit, or touch code
   that was recently churned for a related reason.
2. **Prior-review pass** — if the branch targets a repo with history, read
   comments/learnings from prior reviews on these files
   (`~/.claude/skills/gstack/bin/gstack-review-read`, plus any PR comments
   reachable via `gh pr view`/`gh pr list` when a GitHub remote exists). Re-apply
   any guidance that still holds against the current diff. (Phase 0 already
   extracted the *dismissed* fingerprints into `prior-dismissals.md` — this pass
   mines the rest: advice that was accepted, and comments that were never
   findings at all.)
3. **Code-comment-compliance pass** — read the comments and docstrings in the
   modified files; flag changes that now violate an invariant, contract, or
   "must/never" note stated in-code.
4. **CLAUDE.md-compliance pass** — locate the root CLAUDE.md and any CLAUDE.md in
   the modified directories; flag diff lines that violate a rule those files
   state explicitly. (Do not invent rules — the file must actually call it out.)

Dropped-dimension passes (the coverage Anthropic explicitly skips — run them):

5. **Correctness & error-handling pass** — logic bugs, off-by-one, wrong
   operator/boundary, unhandled error paths, swallowed exceptions, missing
   rollback/cleanup, partial-failure states.
6. **Concurrency & resource pass** — races, TOCTOU, deadlock/lock-ordering,
   unbounded growth, leaked file handles / sockets / connections / goroutines,
   missing timeouts.
7. **Test-coverage-gap pass** — for each new/changed behavior, is there a test
   that would fail if the behavior regressed? Name the specific untested branch.
   (Per jjstack TDD: an untestable behavior is a finding, not an excuse.)
8. **Security pass** — even when gstack's Security specialist ran, re-sweep for
   the OWASP-class issues on the diff (injection, authz/authn gaps, secret
   exposure, unsafe deserialization, SSRF, LLM trust-boundary). Cross-reference
   `references/owasp-security/` if present.

Evidence-pack passes (these exist only because Phase 0 ran — they read files the
diff does not contain, and no diff-only pass can produce them):

9. **Blast-radius pass** — work `{OUTPUT_DIR}/preflight/blast-radius.md` (the
   ONE map, built in Phase 0 — see Module G.1) symbol by symbol. For each
   call site listed, open it and answer: does it still hold against the NEW
   definition — arity, argument types, contract, constant's new value, and every
   enum member still handled at every switch/match/dispatch? A broken call site
   is a P0 even though it appears in no hunk. Report the map's own limits as a
   known gap — quote its `diff scope:` line, and add: files under this repo root
   only; blind to dynamic dispatch, reflection, string-keyed lookup and
   serialized data; and if the header says `**TRUNCATED**`, the symbols past the
   cut were never mapped.
10. **Intent-fidelity pass** — compare the diff against the Phase 0 intent
    restatement in both directions: a stated case not implemented, and a
    behavior change the claim never mentions. If no claim was recoverable, this
    pass reports that as a gap rather than inventing one.

Merge all Phase 4 findings with the Phase 2 findings and dedup by file:line +
claim before verification.

---

## Phase 4.5: Stale-API check

Derived from the Macroscope research (`references/vendor-lessons-macroscope.md`,
which also records what was rejected as marketing and why). Backed by a
deterministic script — the mechanical half is mechanical, so no model does it by
hand. Run it after the Phase 4 merge and before Phase 5.

*This section originally also carried a blast-radius pass. It was dropped, not
lost: blast radius is computed once, in Phase 0's pre-flight pack, and its map is
already handed to every pass. Three independent PRs each built that scan; running
all three would mean three scans, three output files and three noise profiles for
one question. The `bin/` guard in the smoke suite now enforces the single
implementation.*

### 4.5b Stale-API check — kill the false positives that are simply wrong

A well-documented false-positive class: the reviewer judges a call against the
library API it remembers from training, the library has since moved, and correct
code gets flagged. Macroscope *reports* cutting third-party-library review
comments 55% by looking up current docs instead of trusting recall — a
vendor-adjacent figure, published by the search supplier being promoted, and
`references/vendor-lessons-macroscope.md` says so. The reason this phase exists
is the failure class, which needs nobody's benchmark to believe; do not repeat
the number as an established fact.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-dep-inventory --tsv
```

That prints the versions **this repo actually pins**. Then, for every merged
finding that asserts a third-party library/framework/API is used incorrectly:

1. Find the library in the inventory and note its pinned version.
2. WebSearch the **current official documentation for that version** and confirm
   the asserted misuse is real for it. **One lookup per (library, version)** —
   cache the answer and reuse it for every finding about that same pair; thirty
   findings across five libraries are five lookups, not thirty.
   **Cap the phase at 10 lookups**, spending them on the libraries carrying the
   most findings first; anything left unlooked-up takes step 5 below. This is the
   same self-imposed bound the other expensive pass carries — an unbounded
   per-finding search is how a noise control becomes the slowest phase in the
   review.
3. If current docs show the code is correct as written, **drop the finding** and
   record it in the Phase 5.11 ledger with disposition `refuted` and reason
   `stale-api`, **carrying the doc URL in the claim column**. That URL is now
   ENFORCED — `jjstack-review-triage` rejects a `refuted` row whose claim holds
   no `http`/`https` link and renders nothing (exit 4). Without it the two
   tokens bought exactly the disappearance Invariant 3 denies to `suppress`,
   while the page asserted a documentation check that never happened. "Drop"
   here means *removed from the report*, never *removed from the record* — a
   refuted finding stays inspectable like every other, so a later reader can
   see that this reviewer looked and disproved it rather than never looking.
4. If docs confirm the misuse, cite the doc URL in the finding — it raises the
   Phase 5 confidence score with real evidence.
5. If the library is absent from the inventory, or docs cannot settle it, keep
   the finding and cap its Phase 5 confidence at 50 (unverified).

Note the asymmetry: this drops findings that are **wrong**, never findings that
are merely low-priority. It costs no recall, which is why it is the one noise
control adopted here.

Read the inventory's exit code — two of them mean opposite things:

- **Exit 3 (no manifests)** — normal in a repo with no external dependencies.
  Note it, skip to Phase 5.
- **Exit 4 (manifests found, nothing parsed)** — the inventory FAILED. Do **not**
  read it as "no dependencies": every stale-API finding would fall to step 5 and
  be capped at 50 while the phase reports success. Treat every library as absent,
  say so in the report, and raise the parse failure itself as a P2 tooling
  finding so it gets fixed.

---


## Phase 5: Verify by ENRICHING — never by deleting

High recall without verification is noise. But a verification pass that *deletes*
findings from a recall-max review is self-defeating: it hands back to a single
unaudited LLM judgement exactly the coverage the previous four phases spent time
and tokens buying. This skill's earlier design scored each finding 0–100 and
dropped everything under 40 — silent deletion, no record, no appeal.

That is fixed here. Phase 5 now follows NVIDIA SkillSpector's meta-analyzer
architecture: the LLM pass is **architecturally forbidden from suppressing**. It
may add explanation, add remediation, and *raise* confidence; it may mark a
finding unconfirmed; it may not remove one. The rationale and sources are in
`references/code-review-best-practices.md` (loaded in Phase 3) under "Enrich, do
not suppress".

### 5a. Ground every pass in line numbers

Wherever this skill feeds file content to a pass — Phase 4's lenses and the
verification below alike — feed it **line-numbered**, never bare:

```bash
~/.claude/skills/jjstack/bin/jjstack-number-lines <file> [--start N]
```

It renders `L100: def foo()`, so a reported line number is something the pass
**copies** rather than counts. Counting is where the "real bug, wrong line"
false positive comes from: the author looks at the cited line, sees nothing
wrong, and dismisses a true finding as a hallucination. Use `--start` when you
feed a chunk of a large file so the numbers still match the real file.

### 5b. Every finding is a struct, or it is not a finding

Each pass emits findings as JSON Lines with **all** of these fields:

| field | why it is required |
|---|---|
| `lens` | which pass found it — the baseline's rule glob keys on this |
| `file`, `start_line` | grounded location (5a) |
| `severity` | `P0`–`P3` (or CRITICAL/HIGH/MEDIUM/LOW, normalized) |
| `confidence` | 0–100 or 0.0–1.0; normalized deterministically, not by eye |
| `message` | the one-line claim |
| `quote` | the verbatim motivating line — unquotable means unverified |
| `explanation` | why it is wrong |
| `remediation` | what to do. **Required at emission time**: a finding nobody can act on is not worth a line in the report. |

Validate and canonicalize the merged set before anything else touches it:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-normalize {OUTPUT_DIR}/findings.raw.jsonl \
  --invalid-out {OUTPUT_DIR}/findings.malformed.jsonl > {OUTPUT_DIR}/findings.jsonl
```

It normalizes confidence (a model emitting `75` and one emitting `0.75` mean the
same thing) and severity, and coerces `start_line`. Exit 1 means some findings
were malformed — they are written to `findings.malformed.jsonl`, never dropped
on the floor. **Fix the emitting pass and re-emit; do not delete the finding.**

Read the exit code, do not assume it: `0` all valid, `1` some malformed (the
valid ones are still on stdout), `2` usage error or unreadable input, `3` an
internal error — stdout holds a PARTIAL set and the run must be repeated, not
reported. Never treat `3` as `1`.

`findings.malformed.jsonl` is rewritten on **every** run, empty included, so it
always describes the run that just finished. Each record carries the source
`line`, the `reason`, and the `raw` input line — read the `reason`, not the
whole record, when you want to know what the tool objected to.

### 5c. Verify each finding — enrich-only

For **each** normalized finding (batch as parallel agents when there are many):

1. **Read the source around the quote.** Confirm the quoted line is really there
   and really means what the finding says.
2. **Write a concrete failure scenario** — the specific input/state that reaches
   the bug and the wrong output/crash/leak it produces. A finding with no
   reproducible failure scenario is a nitpick, not a bug — and it is reported as
   a nitpick, not deleted.
3. **Adjudicate**, and record the adjudication as the finding's *review
   judgment* (this is what the report's judgment column carries):
   - **confirmed** — evidence supports it. You MAY improve `explanation` and
     `remediation`, and you MAY **raise** `confidence`.
   - **unconfirmed** — you could not confirm it from the source. Append the tag
     `llm-unconfirmed` and say in the judgment what you could not establish.

**Hard rules — these are the point of the phase:**

- **Never delete a finding.** Not for low confidence, not for "probably a false
  positive", not to tidy the report.
- **Never lower** a finding's confidence or severity in verification. Enrichment
  is one-directional. A doubt is expressed as `llm-unconfirmed`, not as a
  quietly-reduced number.
- **Unconfirmed findings move, they do not vanish** — into the report's clearly
  labelled `Unconfirmed` section, with the tag visible.
- **Fail closed.** If verification cannot run at all (agent failure, budget
  exhaustion, a pass that errored), pass **every** finding through unchanged,
  mark the report degraded per 5f, and lower the stated confidence in the
  verdict. Showing more findings is safer than silently dropping them.

**Emission scope** (what a pass should never raise in the first place — this is
a scoping rule for Phase 4, *not* a licence to delete in Phase 5):

- Anything a category marked **COVERED** in Phase 0's `exclusions.md` — that
  tooling actually ran and passed here. Categories marked **IN SCOPE** got no
  free pass: do not silence them on the assumption that CI covers them.
- Pure style nitpicks not called out in a CLAUDE.md.
- Pre-existing issues on lines the diff did not touch.

If such an item is already in hand at Phase 5, it is suppressed through the
baseline in 5d — with a reason on the record — not deleted.

### 5d. Apply the committed baseline (how a re-review shows only what is NEW)

Re-running a recall-max review re-reports everything it reported last time. The
answer is not deletion; it is a **committed baseline** that keeps accepted
findings in the output, marked suppressed with a mandatory reason, and stops
them counting as active.

The baseline is the **narrowest rung of the review memory ladder** (Module G.4):
it keys on one finding *instance*, which is the only reason it is allowed to
suppress at all.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-baseline apply {OUTPUT_DIR}/findings.jsonl \
  --baseline "$(git rev-parse --show-toplevel)/jjstack/review-memory/baseline.tsv" \
  > {OUTPUT_DIR}/findings.adjudicated.jsonl
```

Skip it when the repo has no baseline file yet — a missing baseline is normal,
not an error to work around. **Exit 3** means the repo still has the old
`.jjstack-review-baseline.json`: run `jjstack-review-memory-migrate` once, read
the diff, commit it, and rerun.

Creating or extending a baseline is a **human decision that mutes future
reviews**, so do it only when the user explicitly asks. Never generate one
unprompted to make a report look shorter:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-baseline generate {OUTPUT_DIR}/findings.jsonl \
  --reason "triaged <date>: accepted, see jjstack/<review>.md" \
  -o "$(git rev-parse --show-toplevel)/jjstack/review-memory/baseline.tsv"
```

`generate` **extends** the file it points at: existing rules and already
accepted fingerprints are merged forward, so running it on a repo that already
has a baseline never destroys the reasons a human typed. `--replace` is the
explicit way to start over.

Two mechanisms, deliberately aging differently — both live in the same TSV, one
row each:

- **`fingerprint` rows** — machine-generated content hashes, brittle on purpose:
  edit the flagged source and the finding comes back for review. **Prefer these**
  for individually accepted findings.
- **`rule` rows** — human-authored globs over `lens` / `file` / `message`
  (`-` means "unstated", and matches anything), drift-tolerant: they survive
  line shifts and rewording. Reserve them for deliberate, tightly-scoped policy
  exclusions, because a broad rule can hide newly malicious content. A rule that
  states only a universal glob (`file` = `*`) is rejected: it is the "matches
  everything" rule in disguise, and it would mute the whole repo at exit 0.

Every entry of either kind carries a mandatory free-text `reason` **and** a
`code` from the one shared reason-code vocabulary
(`bin/jjstack-review-vocab.tsv`); the script refuses a baseline without a
reason, refuses a rule that names no matching field (a rule that matches
everything is never what anyone meant), and refuses a code whose ceiling is
below `suppress` (`not-reachable`, for instance, may never suppress anywhere).
Suppressed findings never count toward the active total but **remain in the
output**, marked, so the report can show them for audit.

### 5e. Rank, and treat the summary as a prior — not a verdict

Rank active findings by severity (P0→P3), then confidence. Then read the profile
as a **default posture**, which the evidence may move — the profile is where you
start arguing from, not the answer:

| Active findings profile | Default posture |
|---|---|
| Nothing above P3 | `APPROVE` after a quick read of the P3s. |
| P2s only | `APPROVE` only when each P2 is explained; otherwise `CAUTION`. |
| Any P1 | `CAUTION`. `REJECT` unless every P1 is explained, bounded, and deliberate. |
| Any P0 | `REJECT` unless every P0 is explained AND has a landed mitigation. |
| Any unconfirmed P0/P1 nobody read at source | `REJECT` — unread is not the same as fine. |
| A required pass or the verification could not run | Drop one step (`APPROVE`→`CAUTION`, `CAUTION`→`REJECT`) and say so per 5f. |

**Anti-rationalization guardrail — the dominant failure mode of high-recall
review is talking findings away:**

> **Never downgrade an unexplained P0 or P1 finding based only on author
> reputation, repo familiarity, a green CI, the size of the diff, or the overall
> posture.** Only evidence read at the source downgrades a finding.

We key the table on the active-finding profile rather than on a synthesized 0–100
risk number: inventing one would add a precision the inputs do not have. The
posture semantics are NVIDIA's; the band definition is ours.

### 5f. Report format

Write a concise triage report, not a raw dump of every pass's output. Prefer
specific evidence over generic advice; use tables where they make scanning
easier; **omit empty sections**.

```text
## /review: <target>

**Verdict:** {APPROVE | CAUTION | REJECT} — <short meaning>
**Posture:** <profile from 5e> · <active count> active, <n> suppressed, <n> unconfirmed, <n> disproven
**Coverage:** <passes run> / <passes applicable><, degraded: see below>

### Bottom line
2–3 sentences: land it or not, the main risk, and why the posture alone is not
the whole answer.

### Findings
| Sev | Conf | Location | Finding | Review judgment |
|---|---|---|---|---|
| P1 | 80 | src/a.py:112 | <claim> | <why this blocks / is acceptable / is suspicious> |

Each row expands below with its quote, failure scenario, and remediation.

### Unconfirmed  (tagged `llm-unconfirmed` — kept deliberately, not verified)
Same shape. These were NOT deleted; nobody could confirm them at the source.

### Disproven by test  (tagged `DISPROVEN` in 5.8 — kept deliberately, not deleted)
| Sev | Conf | Location | Finding | The test that did NOT go red |
|---|---|---|---|---|

A test written to prove the finding passed. That has two readings and this report
does not choose between them: the finding is false, **or the test is wrong**
(masking fixture, weak assertion, wrong seam). Quote the test so the reader can
judge which. These are NOT deleted and NOT auto-recorded as `rejected` in 5.10 —
a green test is evidence, not the team's decision.

### Demoted (prior decision)  (still active; ranked lower, never rescored)
| Sev | Conf | Location | Finding | Demoted because |
|---|---|---|---|---|
| P2 | 70 | src/b.py:44 | <claim> | rejected 3× as a pattern; see calibration ledger |

For findings this team has repeatedly rejected as a *class*. The distinction this
section exists to protect: **the confidence score is a claim about the code; the
demotion is a claim about the team's prior decision.** Conflating them destroys
both — so a demoted finding keeps its severity and its number untouched and only
moves down the page, with the prior decision stated. It is still active: it is
reported, not suppressed. Only the baseline below, with an explicit human reason,
takes a finding out of the active set.

### Suppressed by baseline  (not active; shown for audit)
| Location | Finding | Suppressed by | Reason |

### Degraded mode
Only when something did not run. Name the pass, why, and what that leaves
unknown — e.g. "the prior-review pass did not run (no GitHub remote), so
previously-agreed guidance was not re-applied; the verdict is semantic-only and
carries lower confidence."

### Guardrails
The conditions under which this verdict holds — 2–5 numbered items. If one
stops being true, the verdict is void.
```

Verdict semantics, kept to exactly these three labels:

- **`APPROVE`** — no active P0/P1, no unexplained risky behavior, the change does
  what it says.
- **`CAUTION`** — risky behavior exists, but it is **documented, necessary,
  bounded, and controllable**. This value exists so a reviewer never has to
  round a real concern to "fine" for lack of a label.
- **`REJECT`** — unexplained P0/P1, a mismatch between what the change claims and
  what it does, or a risk with no bound.

---

## Phase 5.5: Capture durable gstack review references into the repo

The gstack review rubric (checklist, specialist definitions, adversarial and
Review Army procedures) is what *produced* these findings — but it lives only in
the global gstack clone, which `/gstack-upgrade` rebuilds with `git reset
--hard`. Snapshot the long-term-relevant docs into the version-controlled repo
so the review is reproducible and the rubric is auditable at the commit it ran
against. This is deterministic file I/O — no judgment, just copy the allowlist.

```bash
~/.claude/skills/jjstack/bin/jjstack-capture-review-refs {OUTPUT_DIR}/gstack-review-refs
```

The script copies an explicit allowlist — `checklist.md`, `design-checklist.md`,
`greptile-triage.md`, `TODOS-format.md`, every `specialists/*.md` and every
`sections/*.md` — and writes a `PROVENANCE.md` stamping the gstack version and
commit the rubric came from. Build artifacts (`*.tmpl`, `manifest.json`) and the
procedural `SKILL.md` are excluded on purpose.

It overwrites on every run, so the snapshot tracks the current gstack version and
the git diff on those files becomes a visible record of *when the review rubric
changed* — which is the audit trail that makes an old review interpretable.
Commit them alongside the findings (the output-capture step in 6.2 covers this).

If the script exits 3 (gstack review dir missing), note it and continue — the
review still stands, it just isn't snapshot-reproducible.

---

## Phases 5.6–5.10: the post-passes (what a finished review still hasn't done)

Phases 2–5 are all the same activity — read the diff, judge it — repeated by many
lenses. Five blind spots survive every lens, because they are not questions about
the diff's contents. Load the manual once; it carries the rationale and the
procedure for all five:

```bash
cat ~/.claude/skills/jjstack/references/review-post-passes.md
```

Run the five in order. **Any post-pass that is structurally inapplicable is
skipped and REPORTED as skipped, with its reason** — never omitted silently, and
never reported as clean. New findings raised by a post-pass go back through the
Phase 5 verification gate before they reach the report.

### Phase 5.6 — Absence pass

Ask only: *what should have changed and didn't?* Schema without migration, enum
member without its exhaustive consumers, signature without its callers or docs,
branch without a test, config key without a default, error case without a
handler. Run it as a dedicated pass with a fresh context, following the walk-
outward checklist in the reference. Worth running even when every prior phase
found nothing — "found nothing" is what an omission looks like.

### Phase 5.7 — Review the auto-fixes

gstack's Step 5b auto-applies fixes; that code is an unreviewed diff nothing has
looked at. Get it deterministically, then re-review it as a fresh diff from an
unknown author with the full Phase 4 lens set.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-autofix-diff --stat
```

This reads the marker Phase 2 took. Exit 4 = no auto-fixes were applied → SKIP
and say so. Findings here are P1 by default — but only against code the marker
attributes to the reviewer. If the output says the baseline fell back to `HEAD`,
the Phase 2 marker was missed: repeat that caveat in the report and do NOT report
the tree's contents as reviewer-authored P1s.

### Phase 5.8 — Prove it with a failing test

For each high-confidence finding, write the test that goes red and RUN it. Tag
each finding `PROVEN` / `DISPROVEN` / `UNPROVABLE`.

**All three tags are enrichments. None of them deletes a finding** — 5c's hard
rule has no exception here. `DISPROVEN` moves the finding into the report's
**Disproven by test** section with the test that failed to go red; it does not
drop it, and it does not by itself record a `rejected` verdict in 5.10. A green
test has two readings — the finding is false, *or the test is wrong* (masking
fixture, weak assertion, wrong seam) — and this pass cannot tell them apart, so
it hands both to the human instead of betting on one. Only the committed baseline
(5d), with an explicit human reason, takes a finding out of the active set.

`UNPROVABLE` is itself a finding — per the jjstack TDD rule an untestable
behavior yields a **failing** test, never a hidden or skipped one. Get deliberate
red tests out of the tree before Phase 5.9.

### Phase 5.9 — Re-run the deterministic sweep

```bash
~/.claude/skills/jjstack/bin/jjstack-review-sweep
```

Exit 0 = clean **and a test runner ran**, exit 1 = the fixes regressed something
(every failed check is a P0; attribute it against the pre-fix baseline before
reporting), exit 4 = no checks available → SKIP and say so, exit 5 = everything
that ran passed but **no test runner was among the checks** → report PARTIAL, name
what was missing, and say the regression question is still open. Never round a 5
up to a clean sweep; re-run with `--cmd "<the project's real test command>"`.

### Phase 5.10 — Calibration persistence

Read the calibration store, use its rank to PLACE findings before the report is
finalized, then record this review's verdicts so the next one starts from
evidence. This is the **widest rung of the review memory ladder** (Module G.4):
it keys on a global pattern class, so its ceiling is `rank` — placement only.

**Rank is placement, never a score.** A `placement=demoted` finding is printed
under 5f's **Demoted (prior decision)** section with its severity and confidence
untouched. Never subtract the rank from a finding's confidence: Phase 5 is
enrich-only, and the score is a claim about the code while the demotion is a
claim about the team's prior decision — conflate them and a genuine P0 can be
arithmetically decayed out of the report by past dismissals of a superficially
similar finding. Only the committed baseline (5d), which requires an explicit
human reason, removes a finding from the active set.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-calibration report
```

Exit 4 = no store yet (first calibrated review) → apply no adjustment, say so,
and still record verdicts. Exit 3 = the repo still has the old
`jjstack/review-calibration.tsv`: run `jjstack-review-memory-migrate` once, read
the diff, commit it, and rerun. For each triaged finding:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-calibration record --key <pattern-key> \
  --verdict accepted|rejected --code <reason-code> --lens <pass> --file <path>
```

Key on the CLASS of finding, never the instance. A `rejected` verdict needs a
`--code` from the shared vocabulary — a rejection is a decision, and a decision
is explained. Record nothing for findings the user never ruled on — a guess
pollutes the store.

The store is `{repo}/jjstack/review-memory/calibration.tsv`, alongside its two
siblings.
<!-- BEGIN aikido-lessons — additive section, see references/vendor-lessons-aikido.md -->

## Phase 5.11: Run report — account for every finding, drop none silently

```bash
cat ~/.claude/skills/jjstack/references/vendor-lessons-aikido.md
```

Phases 2 and 4 cast wide; Phase 5 decides what the human reads. The problem is
that the *decisions* evaporate: a finding that quietly leaves the report leaves
no trace, so nobody can tell a reviewer that looked and dismissed from one that
never looked at all. Security scanners solved this long ago — a finding is never
deleted, it is given a **disposition** and a **reason code** and stays
inspectable (the mechanic is drawn from Aikido's triage model; the reference
above records what was adopted and what was rejected as marketing).

**This is not memory.** It is the audit trail of THIS run, regenerated from
scratch every run and living in `{OUTPUT_DIR}`, not in the repo's memory
directory. Four parallel PRs mistook it for a fourth memory store; the tool is
named `jjstack-review-run-report` so that mistake cannot be made again, and it
refuses outright to render a report from a `jjstack/review-memory/` file.

Adopt the accountable half. After Phase 5, write the **complete** merged set —
every finding, whatever became of it — to
`{OUTPUT_DIR}/review-run-findings.tsv`, one finding per line, 7 tab-separated
columns:

```
severity  confidence  path:line  lens  disposition  reason  claim
```

Map Phase 5's outcome onto the disposition, and give every non-reported finding
a reason code from the closed vocabulary. Phase 5 is **enrich-only**, so these
outcomes are dispositions a finding *arrives with* — none of them is a licence
to delete, and no arithmetic threshold appears here:

| Phase 5 outcome | disposition | reason |
|---|---|---|
| confirmed, in the main report | `report` | `-` |
| tagged `llm-unconfirmed` (§5b) | `unconfirmed` | `unverified` |
| demoted by calibration (§5.10) | `demoted` | `prior-decision` |
| retired by the committed baseline (§5d) | `suppress` | `baseline` |
| real but out of scope for this diff | `defer` | `pre-existing` / `not-reachable` / `accepted-risk` |
| raised, then DISPROVED by evidence (§4.5b) | `refuted` | `stale-api` |
| never raised — outside Phase 4's emission scope | `out-of-scope` | `tool-covered` / `style-only` / `no-repro` / `duplicate` |

`reason` is a **code from the closed vocabulary**, never free text. The codes
come from `bin/jjstack-review-vocab.tsv` — the same closed vocabulary the three
memory stores validate against. There is exactly one list. A
baseline-suppressed finding takes the literal token `baseline`; the human
sentence that justified the suppression already lives in the committed
`jjstack/review-memory/baseline.tsv` and stays there. Pasting it into this
column makes the validator exit 4 on a findings file that says exactly what it
was told to say, and the loop has no way out.

`refuted` is the one row where the finding leaves the report because it is
**wrong**, and it is the only row whose decision is made *before* Phase 5 — the
§4.5b stale-API check, which weighs the finding against current official
documentation rather than against a model's judgement. That is why it does not
breach the enrich-only rule, and why it needed its own row: `out-of-scope` is
defined as *never raised*, which is false here, and `suppress` is the
unexamined-disappearance disposition that Invariant 3 forbids for a P0/P1. A
refuted P1 is legal precisely because it carries external evidence. The pairing
is exclusive in both directions — `refuted` takes only `stale-api`, and
`stale-api` only `refuted` — so it cannot become a general delete hatch, nor be
smuggled onto `suppress` to dodge Invariant 3.

**That external evidence is checked, not assumed (Invariant 5).** Binding the
two LABELS is not the same as requiring the document, and for one round it was
all this rule did: a P0 from the `security` lens, claim text "I do not think
this is real", `refuted` + `stale-api`, exited 0 and rendered under *Refuted —
raised, then disproved against current official docs*. The sentence above
justifies letting `refuted` delete a P1 solely because it "carries external
evidence", so the claim column must actually hold the `http`/`https` URL from
step 3 of §4.5b. It does now: a `refuted` row without one is a validation
failure and nothing is rendered.

**Dispositions are totally ordered, and the page does not depend on row order.**
The merge keeps the weakest — most visible — disposition, ranked

    report < unconfirmed < demoted < defer < out-of-scope < suppress < refuted

`refuted` sits last because it is the strongest removal there is: it asserts
the finding is WRONG, so it may never swallow a member still reported,
deferred or suppressed. That ladder and the closed vocabulary are now the SAME
list inside the script, because they drifted once — `refuted` was added to the
vocabulary and not to the ranking, fell into a shared default bucket, tied with
`suppress`, and the identical two rows rendered under *Refuted* or under
*Suppressed by baseline* depending on which line came first. Every field of a
merged record is now the minimum of a total order over the group, the lens list
is sorted, findings render in a fixed (severity, location) order, and a collapse
is listed in **Merges** whenever the group held more than one severity or
disposition — so the rendered report is a function of the SET of findings, not
of the order they were written down.

`stale-api` is also the one reason code no memory store may hold. Its ceiling in
`bin/jjstack-review-vocab.tsv` is `none`, so `baseline generate --code
stale-api`, `ledger --record --code stale-api` and `calibration record --code
stale-api` all exit 4. A refutation is evidence gathered against current docs in
ONE run; remembering it would suppress a future finding with no doc URL and
nothing having consulted any documentation. Record the refutation in that run's
report, not in the repo's memory.

Then render the report. This is deterministic — dedup, merge, corroboration
counting, path-exposure classification, vocabulary validation, reconciliation
and the tally are the script's job, not the model's:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-run-report {OUTPUT_DIR}/review-run-findings.tsv \
  --reconcile {OUTPUT_DIR}/findings.adjudicated.jsonl \
  --out {OUTPUT_DIR}/review-run-report.md
```

Pass `--reconcile` whenever 5d ran: it counts findings per `file:start_line` on
both sides and refuses to render if the findings file is short, which is what turns
"write the **complete** merged set" from an instruction into a checked fact.
A `path:N-M` findings row reconciles on its **start** line. An adjudicated file
holding no findings earns no stronger header than no flag at all — reconciling
against nothing checks nothing. Without the flag the rendered header says so
rather than certifying what nobody verified; drop it only when the repo has no
baseline and 5d produced no adjudicated file.

The script enforces three invariants that prose cannot:

1. **No silent drop** — any disposition other than `report` must carry a reason
   code. Together with the enrich-only rule in Phase 5, this closes the loop:
   Phase 5 cannot delete a finding, and this report cannot let one leave without
   a stated reason on the record.
2. **A reason may not outrank its ceiling** — every code in the shared
   vocabulary declares the strongest verdict it may carry, so
   `not-reachable` (ceiling `demote`) is legal only with `defer` or `demoted`.
   Code that is unreachable today becomes
   reachable at the next refactor, and a reviewer that deleted the finding has
   no way to bring it back. Even the scanner vendors hold this line: their stated
   policy is that in ambiguous cases they "err on the side of caution: instead of
   suppressing a potentially relevant issue, [they] will either keep it as-is or
   lower its severity." You have less call-graph evidence than they do, so hold it
   harder — uncertainty always resolves toward keeping the finding.
3. **Top severity is never suppressed** — a P0/P1 may be deferred with a stated
   reason; it may not be made to disappear.

All three run per row on the way in. Rows that share a fingerprint then
collapse into one finding carrying the **highest severity** of its members —
along with that member's claim and confidence — and their **weakest**, most
visible **disposition**, ranked `report` < `unconfirmed` < `demoted` < `defer` <
`out-of-scope` < `suppress`. A suppressed nit therefore cannot absorb a reported
P0 that happens to share its location and opening phrase; suppression by
absorption is still suppression, and a per-row check cannot see it.

Preserving severity is not enough, because a merge can lose the **claim**.
An equal-severity collision is still a merge: two distinct P0s at one line are
two findings, and collapsing them onto one sentence made the second one's text
vanish from the report entirely while the tally read `report=1`. So the leading
member is (highest severity, then highest confidence), its severity, confidence
and claim always travel together, and **every other member's claim rides on the
same row** with its own severity and confidence (`· also P0/60: …`). A merge
that changed severity, disposition **or the finding text** is listed in the
report's own **Merges** section, so the collapse stays as auditable as
everything else.

The collapse is then **checked rather than trusted**: the script recomputes the
merged record from an independent per-member tally and renders nothing if the
two disagree. Re-running the same three invariants on the collapsed row would
be dead code — the per-row pass has already rejected every input that could
violate them — so what the merged pass actually guards is the fidelity of the
merge itself.

It exits **4** and renders nothing if any of those is violated, or if
`--reconcile` finds a finding with no row: fix the findings file and rerun
rather than working around it. It exits 3 if the findings file or the
adjudicated file is missing, and **2 if you point it at a
`jjstack/review-memory/` store** — that is the rename made structural. It also
emits yellow `ADVISORY` lines for findings reported against vendored or
generated paths — code nobody here authored, and usually noise — and for an
empty, unreconciled findings file, which certifies nothing.

Two things it gives you for free that the model should not be doing by hand:
**dedup with a corroboration count** (the same defect found by three lenses is
one finding with `corrob 3`, and that agreement is itself a ranking signal —
rank the main report by severity, then corroboration, then confidence), and
**exposure class** (`prod` / `test` / `fixture` / `vendor` / `generated` /
`docs`), a deterministic blast-radius annotation. Exposure *annotates*; it never
decides whether a finding is shown.

Pipes in a claim are escaped for you — a finding quoting `a || b` used to render
a 9-cell row against a 7-cell header, and the renderer dropped the overflow.

Commit `review-run-report.md` alongside the findings report — it is the record
of what this review chose not to tell you, and why. It is per-run output: the
next run writes a fresh one, and nothing in it is consulted by a later review.
What a later review DOES consult is the memory ladder in Module G.4.

<!-- END aikido-lessons -->

---

## Phase 6: jjstack finish

### 6.1 Quality iteration loop

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol exactly, using the current review document as
the target. Iterate to `MIN_SCORE` (default 10/10) or `MAX_ITERATIONS`.

### 6.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol — the full report from 5f (findings,
unconfirmed, baseline-suppressed, degraded mode, guardrails) lands in
`{OUTPUT_DIR}` alongside the normalized `findings.jsonl` it was rendered from,
together with the `gstack-review-refs/` snapshot from Phase 5.5. All are
committed to the repo so the findings, the machine-readable record, and the
rubric that produced them travel together. If this run wrote or updated anything
under `{repo_root}/jjstack/review-memory/` — the baseline (5d), the ledger
(G.3) or the calibration store (5.10) — commit those too. They are what makes
the next review show only what is new, and each change is a one-line diff a
human can review.

### 6.3 Post the review to the PR

A report nobody sees is a review that did not happen. Everything above lands in
`{repo}/jjstack/`, which nobody opens unless they already know it is there. If
this branch has a pull request, the review goes **on the PR**.

```bash
cat ~/.claude/skills/jjstack/references/pr-comment-voice.md
```

That reference is the voice. The jj in jjstack is Jesper Jurcenoks and a review
posted under this name sounds like he wrote it: conclusion first, one line per
finding, no selling. Read it before composing.

Detect the PR. No PR is a legitimate outcome, not an error:

```bash
gh pr view --json number,url --jq '"PR #\(.number) \(.url)"' 2>/dev/null || echo "NO_PR"
```

If `NO_PR`: say so in the session output and stop here. Never invent a PR, and
never post to a different one.

Compose the comment to `{OUTPUT_DIR}/pr-comment.md` following the structure in
the reference. **The comment is a doorbell, not the delivery** — verdict, the
blocking findings only, and a link to the full report committed in 6.2.

Then lint it. This is a **HARD GATE** per
`references/hard-gate-convention.md`. Bold prose saying "do not post if it fails"
is not a gate — a gate is one command where the post cannot run unless the check
passed, so the lint and the post are chained and the shell enforces the order:

```bash
~/.claude/skills/jjstack/bin/jjstack-pr-comment-lint {OUTPUT_DIR}/pr-comment.md && gh pr comment --body-file {OUTPUT_DIR}/pr-comment.md
```

Never run the post as its own step. Two separate fenced blocks let a failed lint
be followed by a successful post, which is the exact failure the convention
names. If the lint exits non-zero, fix the comment and run the chained command
again.

It enforces what a machine can decide: 12 lines / 900 chars, at most 3 findings
inline, a mandatory link, no emdash, no superlatives, no meta-commentary, no
softening qualifiers, no sentence over 180 chars. A prose instruction to "be
brief" loses to the pull toward completeness on every run, so the budget is
code.

When it reports `too-long` or `too-many`, **move findings into the report, never
delete them.** Cutting a finding to fit the budget is the one failure this whole
skill exists to prevent. The report already holds all of them; the comment shows
what blocks the merge.

The post already happened in the chained command above, and only if the lint
passed. There is deliberately no separate post step to reach for.

If `dna.voice` is set in the jjstack config, load it first and let it govern the
prose — the reference above is the review-scoped subset of that voice, and the
full DNA wins where the two differ.

### 6.4 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.

---

## Module G: repo-context inputs + the review ledger (Greptile lessons)

Self-contained additive module. It does not replace any phase above; it feeds
two of them.

**When it runs:**
- The two **scans** run at the **start of Phase 4**, before the parallel passes
  launch. Their output is context every pass gets, not a pass of its own.
- The **ledger match** runs at the **end of Phase 5**, after each finding already
  has its confidence score — never before, so a prior dismissal can never stop a
  finding from being verified on its own merits.

Rationale, sourcing, and the explicit list of what was rejected as marketing:

```bash
cat ~/.claude/skills/jjstack/references/vendor-lessons-greptile.md
```

### G.1 Cross-file blast radius (computed in Phase 0 — do NOT run it again)

A diff-only reviewer structurally cannot see the callers of the function the
diff just changed. This is the defect class repo-context reviewers genuinely
catch and diff-only reviewers genuinely cannot — so compute it deterministically
instead of hoping a pass wanders into it.

That computation already happened. **Phase 0's pre-flight pack runs
`jjstack-review-blast-radius` once** and writes the map to
`{OUTPUT_DIR}/preflight/blast-radius.md`; Phase 4's blast-radius pass (pass 9)
reads that file. This module is the *explanation* of that map, not a second
invocation — running it again here would produce two files with the same
basename in two directories and leave passes disagreeing about which is current.
Three independent PRs each built this scan; the point of the consolidation was
one implementation, run once.

If the diff touches a shared module whose consumers live in a sibling repo, add
`--also-repo <path>` once per sibling **to the Phase 0 pre-flight invocation**,
before it runs — not to a second run here.

Feed the report to every Phase 4 pass. For each listed site, the question is:
**does the changed definition still satisfy this out-of-diff caller?** A site
that no longer holds is a P0 that the diff alone cannot show — and it is exempt
from the "review the diff, not the whole file" rule in
`code-review-best-practices.md`, because the diff is what broke it.

Absence of sites is weak evidence, never proof: the map is textual, so dynamic
dispatch, reflection, string-keyed lookup and cross-language callers are
invisible to it. Never report "no external callers" as a safety claim.

### G.2 Revert and incident history (start of Phase 4)

A file that has been reverted or hotfixed before is a higher review risk than
one that never has, and the diff never shows it.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-revert-history > {OUTPUT_DIR}/revert-history.md
```

This is a pre-computed input to the **git-history pass (Phase 4.1)**, which
should read the named commits rather than re-deriving them. A change that
reintroduces the condition behind a listed revert, or removes the guard added to
fix it, is a P0 finding.

If the report's header says **TRUNCATED: this is a shallow clone**, the search
did not run over the stated window — `git log` could only see the fetched depth
(`actions/checkout` fetches one commit by default). An empty result there is
evidence about the checkout, not about the code. Treat the git-history pass as
**not run**, say so in 5f's Coverage line, and drop the verdict one step per the
degradation rule rather than reading silence as a clean history.

### G.3 Ledger match — demote, never drop (end of Phase 5)

The ledger is the **middle rung of the review memory ladder** (G.4): it keys on
a path glob plus a category, so its ceiling is `demote`.

After every finding has a confidence score, check each against the repo's
ledger of what past reviews decided:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-ledger --match --path <file> --category <cat>
```

- **Exit 0 (`DEMOTE effect=demote …`)** — a prior review dismissed this class here. File the
  finding under 5f's **`### Demoted (prior decision)`** section and quote the
  ledger's note as the reason. Do **not** drop it, and do not lower its
  confidence score: the score is a claim about the code, the demotion is a claim
  about the team's prior decision, and conflating them destroys both.

  **Demotion is idempotent and terminal.** Two independent mechanisms can demote
  the same finding — this ledger (path + category) and Phase 5.10's calibration
  rank (global pattern class). A finding matched by both is demoted **once**: it
  appears in `Demoted (prior decision)`, still active, still carrying its own
  severity and confidence. Demotions never stack, never compound, and can never
  add up to a suppression. Only the committed baseline (5d), which requires an
  explicit human reason per entry, removes a finding from the active set.
- **Exit 1** — no prior decision applies. Report normally. A `PROTECTED …` line
  on exit 1 means a dismissal exists **whose path glob matches this finding**
  but whose category never demotes; report the finding at full weight and
  mention the prior dismissal in the finding body. A `PROTECTED` line always
  refers to this path — never cite a dismissal the tool did not print.
- **Exit 1 with a `no ledger at …` warning on stderr** — this is *not* the same
  statement. Nothing was consulted, usually a mistyped `--ledger`/`--repo`.
  Report every finding normally and do **not** describe the ledger as checked.
- **A `warn … too broad` line on stderr** — a row in the ledger matches across
  unrelated parts of the repo, so it was ignored rather than acted on. Report the
  finding normally, and say in the report that a blanket row is sitting in the
  ledger and should be scoped or deleted.

Record outcomes only for findings the user actually adjudicates in this session:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-ledger --record --type <dismissed|fixed|confirmed> \
  --path <glob> --category <cat> --code <reason-code> --note "<why>"
```

Never record a dismissal the user did not make. An invented dismissal is a
permanent, self-inflicted blind spot in every future review of this repo.

Scope `--path` to the place the decision was actually about (`src/legacy/*`,
`docs/*`). Breadth is judged on what the glob **matches**, not on how it is
spelled: the tool runs the pattern against a corpus of unrelated probe paths and
rejects it with exit 2 if it reaches across three or more unrelated top-level
names. `*`, `*/*`, `*[a-z]*`, `[a-z]*`, `*.*` and every other spelling of "the
whole repo" fail the same test, because the test is on the semantics. Such a
glob would demote every future finding in that category repo-wide while reading
like any other line in a diff.

The same test is applied to patterns **read from** the ledger. This file is
meant to be hand-edited and merged in git, so a blanket row can arrive without
passing through `--record`; `--match` prints a `warn … too broad` line to stderr
and ignores that row. The row stays in the file as history — it just never
suppresses anything. If you see that warning, scope the row or delete it.

`--note` is stored in the printable alphabet: anything outside it (a newline
first of all, but equally a tab or a control character) is escaped with the
standard `printf %b` sequences, so the note is always exactly one field on
exactly one line and always decodes back to what you typed. A multi-line note is
therefore safe to pass and comes back whole.

The `<repo>` column names the repo the **ledger** belongs to, resolved from the
ledger's own location — not from wherever your shell happens to be — so a ledger
copied or merged between repos still says what it is about. Pass `--repo` to
override it explicitly.

The ledger lives at `{repo_root}/jjstack/review-memory/ledger.tsv` — in git, so
a demotion is reviewable in a PR and retiring one is a one-line diff. Commit it
with the findings in step 6.2. **Exit 3** means the repo still has the old
`jjstack/review-ledger.md`: run `jjstack-review-memory-migrate` once, read the
diff, commit it, and rerun.

### G.4 The review memory ladder — three stores, one directory, one format

Three things carry across reviews, and they are **not** three copies of one
idea. They are an escalation ladder: **the narrower the key, the stronger the
verdict it may emit.**

| store | key scope | ceiling | file |
|---|---|---|---|
| `jjstack-review-calibration` | a global **pattern class** | `rank` (placement only) | `jjstack/review-memory/calibration.tsv` |
| `jjstack-review-ledger` | a **path glob + category** | `demote` | `jjstack/review-memory/ledger.tsv` |
| `jjstack-review-baseline` | one finding **instance** (file + line + claim) | `suppress` | `jjstack/review-memory/baseline.tsv` |

Collapsing them into one store would flatten the property that stops a global
heuristic from silently suppressing a specific P0. So they stay three files —
but they now share one directory, one format, and one reason-code vocabulary.

- **One directory** so the whole of a repo's review memory is one `git log`.
- **One format — TSV** because the review value of these files IS their diff: a
  suppression is one line, so it shows as a one-line PR diff and it greps. JSON
  is the worst choice for a file read as a diff; Markdown the worst for a file a
  script must parse.
- **One vocabulary** — `bin/jjstack-review-vocab.tsv` — read by all three stores
  *and* by the per-run report of Phase 5.11. It also declares the ladder itself,
  so the ceilings are data, not convention: a calibration row that claims
  `suppress` is rejected with **exit 4** by arithmetic, not by anyone
  remembering the rule. Each tool also refuses a store from another rung.

**Demotion is idempotent and terminal.** A finding hit by both the ledger and a
negative calibration rank is demoted **once** — active, printed, severity and
confidence untouched. Demotions never stack into a suppression; only the
instance-keyed baseline, with a mandatory human reason per entry, takes a
finding out of the active set.

Migration from the pre-1.0 layout is explicit, never automatic — these files are
version controlled and a tool that silently rewrote one mid-review would produce
a diff nobody approved:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-memory-migrate --repo "$(git rev-parse --show-toplevel)"
```

Read the new files, delete the legacy ones, and commit both in one diff.
