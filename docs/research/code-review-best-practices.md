# AI code-review best practices — the research behind `/review`

**Research, not doctrine.** Nothing loads this file at runtime; `/review`'s
actual rules live in `skills/review/SKILL.md`. It is kept because the sourcing
is worth having when the skill is next changed.

It records how the reference reviewers are tuned and what the literature says
about the precision/recall trade. Read the caveat under "jjstack's move" before
taking any of it as a recommendation: jjstack tried the recall-max end of this
curve and abandoned it.

## How the reference peers are tuned (know what you are beating)

- **Anthropic `/code-review` (official plugin)** — Haiku eligibility check →
  gather CLAUDE.md → Haiku PR summary → **5 parallel Sonnet passes**
  (CLAUDE.md-compliance, shallow diff bug-scan, git blame/history,
  prior-PR-comments, code-comment-compliance) → per-finding **Haiku 0–100
  confidence score** with a fixed rubric → **filter < 80** → post a brief cited
  comment. It deliberately **skips** security, test coverage, and general
  quality, and reports only diff-introduced bugs. Efficiency-first, PR-shaped.
- **gstack `/review`** — critical categories (SQL, races, LLM trust boundary,
  shell injection, enum completeness), a pre-emit verification gate (must quote
  the motivating line), and a "Review Army" of specialists (Testing,
  Maintainability, Security, Performance, Data Migration, API Contract, Design,
  Simplification) with **adaptive gating**: skips all specialists on diffs
  < 50 lines, gates several under 100 lines, and auto-gates specialists that
  have found nothing in 10+ runs.

**jjstack's move, as of v0.3.0 — and the correction that produced it.** The
first attempt did exactly what this section used to recommend: run the union of
both tools' passes, force every specialist regardless of gating, never drop a
finding. Measured over the nine PRs that built it, that reviewer produced
14,906 insertions against 112 deletions, ~230 findings of which 75% were P2/P3,
and a P2/P3 count that ROSE every round while P0/P1 fell. It never converged.

What replaced it keeps the cheap half — run the repo's real tooling first, map
the callers outside the diff, read the stated intent — and puts a budget on the
expensive half: gstack's own gating applies unless `--deep` is passed, four
passes rather than ten, ten findings in the report, and a re-review that
verifies only the prior P0/P1 and returns `STOP` if the count did not fall.
Practice 12 below is therefore stated too strongly for this codebase: high
recall is defensible only when someone has measured that it finds more real
bugs, and nobody had.

## Ranked best practices (what / why)

1. **Gate on an explicit numeric confidence score.** Anthropic's own
   security-review reports only findings above a stated bar ("below 0.7, don't
   report"); a numeric self-scored threshold turns "maybe" into a hard filter —
   the single biggest lever on false-positive rate.
2. **Require a concrete failure/exploit scenario for every finding** — the input
   that triggers it and the wrong result it produces. A finding that can't name a
   repro is usually a hallucination or a nit, so the requirement both filters
   noise and makes real bugs actionable.
3. **Bias toward misses over noise for LOW-severity items** — "better to miss a
   theoretical issue than flood the report." Alert fatigue destroys trust; once
   it sets in, ~40% of alerts get ignored regardless of validity.
4. **Review the diff, not the whole file** — flag only what the change
   introduces or newly exposes. Scoping to the delta stops the reviewer from
   relitigating pre-existing code and drowning the author in out-of-scope
   comments.
5. **Give each pass surrounding context, not just the hunk** — the full changed
   files plus repo/architecture awareness. Cross-file context catches the defect
   classes diff-only review misses (auth logic, cross-service contracts, state
   bypass) and prevents false alarms about symbols defined elsewhere.
6. **Run an understanding/plan pass before judging** — restate what the change
   does, then critique. Grounding in intent first prevents confidently-wrong
   findings that misread the change's purpose.
7. **Use narrow, single-focus passes (sub-agents) rather than one
   "find-anything" prompt.** Specialized passes don't share a single reviewer's
   blind spots and each stays in its confidence lane — the basis of the
   multi-agent fan-out.
8. **Self-verify each finding before emitting: "would a senior engineer
   confidently raise this in a PR?"** A final professional-standard gate strips
   speculative and style-only comments the model would otherwise pad the list
   with.
9. **Label every comment nit / concern / must-fix and rank by severity.**
   Explicit labels let the author trust and triage instantly, and let you
   suppress nits by default.
10. **Maintain an explicit exclusion list and suppress already-dismissed
    findings.** Naming what NOT to report (style, linter-catchable, deliberate
    patterns, prior-dismissed) matters as much as what to report; repeat
    findings are pure fatigue.
11. **Never re-report what a linter, formatter, type-checker, or compiler
    catches.** Assume CI runs them. Style nitpicking from an LLM is expensive
    noise for a job deterministic tooling does for free.
12. **Choose your precision/recall stance deliberately.** High recall is
    defensible only when the AI filters first and a human reads the survivors —
    which is exactly this skill's shape (Phase 4 casts wide, Phase 5 verifies).
    That is why jjstack's main-report gate can sit lower (≥ 60/100) than
    Anthropic's 80: the failure-scenario requirement and self-verification do the
    filtering the higher bar would otherwise do, and the 40–59 band survives in
    an appendix rather than being dropped blind.

## Dimensions checklist (sweep each; skip only if structurally inapplicable)

- Correctness / logic bugs, off-by-one, wrong conditionals, edge cases
  (null / empty / boundary).
- Security — injection, authz/authn bypass, unsafe deserialization, secret
  handling, XSS, SSRF, LLM trust boundary.
- Concurrency / race conditions, shared mutable state, lock ordering, TOCTOU.
- Error handling — swallowed errors, wrong recovery, missing cases, partial
  failure / missing rollback.
- Resource leaks — unclosed handles / connections, unbounded growth, missing
  timeouts.
- API / contract misuse — wrong call, cross-service contract violation,
  state-machine bypass.
- Test-coverage gaps — new logic untested; would the test fail when the code
  breaks? (Per jjstack TDD, an untestable behavior is a finding, not an excuse.)
- Performance — N+1, needless allocation, hot-path cost — only when materially
  impactful.
- Readability / complexity / naming — always as `nit`, never blocking.

## Anti-patterns / do-not

- Reviewing whole files instead of the diff; relitigating pre-existing code.
- Style nitpicking a linter should catch.
- Vague findings with no repro, no location, or no concrete consequence.
- Flooding with LOW-severity noise; unlabeled findings the author must triage
  blind.
- Reporting theoretical issues to look thorough; padding the list.
- Re-flagging findings already dismissed or acknowledged in a prior review.

## Sources

- [Anthropic claude-code-security-review — prompts.py](https://github.com/anthropics/claude-code-security-review/blob/main/claudecode/prompts.py) — primary: confidence tiers, exploit-scenario field, HIGH/MEDIUM gating, exclusion list.
- [anthropics/claude-code-security-review (repo)](https://github.com/anthropics/claude-code-security-review) — multi-agent narrow-scope + high-confidence framing.
- Anthropic `/code-review` plugin (`claude-plugins-official/code-review`) — the 5-pass fan-out + 0–100 confidence rubric + <80 filter analyzed above (inspected locally).
- [Google eng-practices — what to look for in a review](https://google.github.io/eng-practices/review/reviewer/looking-for.html) — canonical review dimensions; the `Nit:` convention.
- [Augment — deep code review: recall vs precision](https://www.augmentcode.com/guides/deep-code-review-recall-vs-precision) — precision/recall economics, repo-context multi-pass, learning from dismissals.
- [Propel — reducing AI review false positives](https://www.propelcode.ai/blog/ai-code-review-false-positives-reducing-noise) — nit/concern/must-fix labels, dismissal learning, suppression, policy-first.
- [CodeAnt — how many false positives are too many](https://www.codeant.ai/blogs/ai-code-review-false-positives) — per-category FP tolerances; alert-fatigue signal loss.
- [Pickuma — CodeRabbit vs Greptile vs Diamond 2026](https://pickuma.com/for-dev/ai-code-review-tools-coderabbit-greptile-diamond-2026/) — vendor positions on the precision/recall curve.
