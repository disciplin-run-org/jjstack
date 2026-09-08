---
name: review
version: 0.2.0
description: |
  The deepest, highest-recall pre-landing review in the stack. Wraps gstack's
  /review but deliberately trades time and tokens for COVERAGE: it forces every
  specialist to run (no adaptive gating, no small-diff skip), adds the review
  passes that Anthropic's /code-review and gstack both skip (security, test
  coverage, performance, concurrency, resource leaks, error handling, API
  misuse, git-history context, prior-PR comments, code-comment + CLAUDE.md
  compliance), then controls the resulting noise with per-finding
  self-verification instead of suppressing whole dimensions. Saves findings to
  {repo}/jjstack/, injects DNA, iterates to 10/10. Use on the diff about to merge
  when you want to catch what a fast review would miss.
  Trigger on: "review my changes", "pre-landing review", "review the diff",
  "review before merge", "deep review", "adversarial review", "review this PR",
  "catch everything review", "thorough review".
  Do NOT trigger for: a fast/cheap pass (use gstack /review or the code-review
  plugin directly), a specific PR by number for a quick comment (use
  /smart-review or the code-review plugin), security-only review
  (use /security-review), two-stage spec-then-quality review
  (use /two-stage-review), processing incoming review feedback
  (use /receiving-code-review), or design/UI review (use /design-review).
  NOTE: this skill takes the name /review, which Claude Code v2.1.223+ also
  uses as a built-in alias of /code-review. Typing /review reaches this skill,
  not Claude's. For Claude Code's own reviewer - the one that takes a PR
  number, effort levels, --comment and --fix - type /code-review.
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

**Design provenance:** the multi-agent fan-out, the git-history / prior-PR /
code-comment / CLAUDE.md-compliance passes, and the confidence-scored
self-verification gate are drawn from Anthropic's official `/code-review`
command and folded on top of gstack's Review Army. The best-practices behind
the extra passes and the noise-control are documented (with sources) in
`references/code-review-best-practices.md`, loaded in Phase 3.

Four enhancements over the gstack base:
1. **Recall-max delegation** — force all specialists, disable adaptive gating
   and the small-diff skip, run extra adversarial passes.
2. **Superset dimension sweep** — add the passes gstack + Anthropic skip.
3. **Self-verified findings** — every finding carries a concrete failure
   scenario and a verified confidence score; this is how recall stays usable.
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
concurrently.** Each agent returns a list of findings; each finding MUST name
the file:line, the lens that flagged it, and (per Phase 5) a concrete failure
scenario. Skip a pass only when it is structurally inapplicable (e.g. no prior
PRs on a brand-new repo), never merely to save tokens.

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

## Phase 5: Self-verify every finding (this is how recall stays usable)

High recall without verification is just noise. Before any finding reaches the
user's report, it passes an adversarial self-check that unions gstack's pre-emit
gate with Anthropic's 0–100 confidence scoring.

For **each** merged finding, run the verification (batch them as parallel agents
when there are many):

1. **Quote the motivating code** — file:line plus the verbatim line(s) that
   trigger the finding. If you cannot quote it, the finding is unverified.
2. **Write a concrete failure scenario** — the specific input/state that reaches
   the bug and the wrong output/crash/leak it produces. A finding with no
   reproducible failure scenario is a nitpick, not a bug.
3. **Score confidence 0–100** using this rubric (from Anthropic's `/code-review`):
   - **0** — false positive under light scrutiny, or a pre-existing issue on
     unmodified lines.
   - **25** — might be real, could not verify.
   - **50** — verified real, but a nitpick or rare in practice.
   - **75** — verified, very likely hit in practice; approach is insufficient.
   - **100** — certain; evidence directly confirms it will happen frequently.
4. **Gate.** Report findings scoring **≥ 60** in the main report (a deliberately
   more permissive gate than Anthropic's 80 — this skill is tuned for recall).
   Findings scoring 40–59 go to an **appendix** ("verify — medium confidence"),
   never dropped silently. Findings < 40 are dropped.
5. **Rank** the main report by severity (P0→P3) then confidence.

**Do NOT report** (these are noise, per `references/code-review-best-practices.md`):
- Anything a linter / typechecker / formatter / compiler would catch — assume CI
  runs them.
- Pure style nitpicks not called out in a CLAUDE.md.
- Pre-existing issues on lines the diff did not touch.
- Findings with no quotable motivating line or no failure scenario.

Finding format:
`[SEVERITY] (confidence: N/100) file:line — description | failure scenario: <input → wrong output>`

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

Follow the output capture protocol — the full findings report (main +
appendix), with the confidence scores and failure scenarios, lands in
`{OUTPUT_DIR}`, together with the `gstack-review-refs/` snapshot from Phase 5.5.
Both are committed to the repo so the findings and the rubric that produced them
travel together.

### 6.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.
