---
name: review
version: 0.3.0
description: |
  The deepest, highest-recall pre-landing review in the stack. Wraps gstack's
  /review but deliberately trades time and tokens for COVERAGE: it forces every
  specialist to run (no adaptive gating, no small-diff skip), adds the review
  passes that Anthropic's /code-review and gstack both skip (security, test
  coverage, performance, concurrency, resource leaks, error handling, API
  misuse, git-history context, prior-PR comments, code-comment + CLAUDE.md
  compliance), then controls the resulting noise with an enrich-only
  verification pass and a committed baseline — never by deleting findings.
  Emits a three-valued APPROVE/CAUTION/REJECT verdict with per-finding review
  judgments and guardrails. Saves findings to {repo}/jjstack/, injects DNA,
  iterates to 10/10. Use on the diff about to merge when you want to catch what
  a fast review would miss.
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
`references/code-review-best-practices.md`, loaded in Phase 3.

Four enhancements over the gstack base:
1. **Recall-max delegation** — force all specialists, disable adaptive gating
   and the small-diff skip, run extra adversarial passes.
2. **Superset dimension sweep** — add the passes gstack + Anthropic skip.
3. **Enrich-only verification** — every finding carries a quote, a concrete
   failure scenario, a remediation, and a review judgment. Verification may
   enrich a finding or mark it unconfirmed; it may never delete one. Noise is
   controlled by a committed baseline with a stated reason, not by deletion.
4. **jjstack finish** — repo-local output, DNA injection, quality loop to 10/10,
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

## Phase 2: Delegate to gstack — recall-max

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

Context passes (from Anthropic's `/code-review`, adapted from PR to local diff):

1. **Git-history pass** — for each hunk in the diff, read `git log -p` / `git
   blame` on the surrounding lines. Flag changes that reintroduce a
   previously-fixed bug, contradict the intent of a recent commit, or touch code
   that was recently churned for a related reason.
2. **Prior-review pass** — if the branch targets a repo with history, read
   comments/learnings from prior reviews on these files
   (`~/.claude/skills/gstack/bin/gstack-review-read`, plus any PR comments
   reachable via `gh pr view`/`gh pr list` when a GitHub remote exists). Re-apply
   any guidance that still holds against the current diff.
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

Merge all Phase 4 findings with the Phase 2 findings and dedup by file:line +
claim before verification.

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

- Anything a linter / typechecker / formatter / compiler would catch — assume CI
  runs them.
- Pure style nitpicks not called out in a CLAUDE.md.
- Pre-existing issues on lines the diff did not touch.

If such an item is already in hand at Phase 5, it is suppressed through the
baseline in 5d — with a reason on the record — not deleted.

### 5d. Apply the committed baseline (how a re-review shows only what is NEW)

Re-running a recall-max review re-reports everything it reported last time. The
answer is not deletion; it is a **committed baseline** that keeps accepted
findings in the output, marked suppressed with a mandatory reason, and stops
them counting as active.

```bash
~/.claude/skills/jjstack/bin/jjstack-review-baseline apply {OUTPUT_DIR}/findings.jsonl \
  --baseline "$(git rev-parse --show-toplevel)/.jjstack-review-baseline.json" \
  > {OUTPUT_DIR}/findings.adjudicated.jsonl
```

Skip it when the repo has no baseline file yet — a missing baseline is normal,
not an error to work around.

Creating or extending a baseline is a **human decision that mutes future
reviews**, so do it only when the user explicitly asks. Never generate one
unprompted to make a report look shorter:

```bash
~/.claude/skills/jjstack/bin/jjstack-review-baseline generate {OUTPUT_DIR}/findings.jsonl \
  --reason "triaged <date>: accepted, see jjstack/<review>.md" \
  -o "$(git rev-parse --show-toplevel)/.jjstack-review-baseline.json"
```

Two mechanisms, deliberately aging differently:

- **`fingerprints`** — machine-generated content hashes, brittle on purpose:
  edit the flagged source and the finding comes back for review. **Prefer these**
  for individually accepted findings.
- **`rules`** — human-authored globs over `id` (lens) / `path` / `message`,
  drift-tolerant: they survive line shifts and rewording. Reserve them for
  deliberate, tightly-scoped policy exclusions, because a broad rule can hide
  newly malicious content.

Every entry of either kind carries a mandatory `reason`; the script refuses a
baseline without one, and refuses a rule that names no matching field (a rule
that matches everything is never what anyone meant). Suppressed findings never
count toward the active total but **remain in the output**, marked, so the
report can show them for audit.

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
**Posture:** <profile from 5e> · <active count> active, <n> suppressed, <n> unconfirmed
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
rubric that produced them travel together. If Phase 5d wrote or updated
`.jjstack-review-baseline.json`, commit that too — it is what makes the next
review show only what is new.

### 6.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
