# AI code-review best practices — high-recall, self-verified

Operating manual for the jjstack `/review` wrapper. jjstack `/review` is
deliberately tuned for **recall** (catch more, take longer, spend more tokens)
rather than the efficiency stance of Anthropic's `/code-review` and gstack's
default `/review`. High recall is only usable when the reviewer — not the human
— filters first; the practices below are how the noise stays low while the net
stays wide. Each is drawn from a cited source at the bottom.

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
- **NVIDIA `SkillSpector` / `skill-inspector`** — deterministic pattern
  analyzers produce the findings; an LLM meta-analyzer then *enriches* them and
  is architecturally forbidden from suppressing any. A committed baseline
  absorbs accepted findings, a posture table separates score from verdict, and
  the verdict is three-valued. Reviews **skills as artifacts**, not diffs — but
  the review mechanics are the transferable part, and they are the strongest
  published answer to "how do you keep breadth without drowning the reader".

**jjstack's move:** run the union of all three tools' passes, force every
specialist regardless of gating, add the dimensions Anthropic drops, then earn
the low noise back with an enrich-only verification pass and a committed
baseline — never by dropping dimensions and never by deleting findings.

## Ranked best practices (what / why)

1. **Gate on an explicit numeric confidence score — but gate WHERE a finding is
   shown, not WHETHER it survives.** Anthropic's own security-review reports
   only findings above a stated bar ("below 0.7, don't report"); a numeric
   self-scored threshold turns "maybe" into a hard filter and is the single
   biggest lever on false-positive rate. For a tool whose whole thesis is
   recall, though, a threshold that *deletes* spends the coverage it just paid
   for — so the score picks the section, and the baseline (practice 10) does
   the removing, with a reason on the record. See "Enrich, do not suppress".
2. **Require a concrete failure/exploit scenario for every finding** — the input
   that triggers it and the wrong result it produces. A finding that can't name a
   repro is usually a hallucination or a nit, so the requirement both filters
   noise and makes real bugs actionable.
3. **Bias toward misses over noise for LOW-severity items** — "better to miss a
   theoretical issue than flood the report." Alert fatigue destroys trust; once
   it sets in, ~40% of alerts get ignored regardless of validity. jjstack
   satisfies this by **tiering**, not by missing: low-confidence and unconfirmed
   items sit in a labelled lower section the reader can skip, so the main
   report stays short without anything being thrown away.
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
    defensible only when the AI *organizes* first and a human reads the top of
    the list — which is exactly this skill's shape (Phase 4 casts wide, Phase 5
    verifies and tiers). That is why jjstack's main-report bar can sit lower
    than Anthropic's 80: the quote, failure-scenario and remediation
    requirements do the filtering the higher bar would otherwise do, and
    everything below the bar is demoted to a labelled section rather than
    deleted.

## Enrich, do not suppress (the SkillSpector architecture)

The five mechanics jjstack `/review` takes from NVIDIA's SkillSpector. They
answer one question: *how does a high-breadth reviewer stay readable without
losing anything?*

1. **The LLM pass may enrich; it may not suppress.** SkillSpector's
   meta-analyzer is built so that "every deterministic finding remains in
   primary output. Unconfirmed findings receive an annotation tag; confirmed
   findings may gain an explanation or higher confidence, but are never
   downgraded." And it fails closed: when the LLM call fails, "we pass ALL
   findings through unchanged… A security tool should fail-closed — showing
   more findings is safer than silently dropping." This is the correction to
   the older jjstack design, which scored findings 0–100 and deleted everything
   under 40: an unaudited LLM pass silently discarding results inside a skill
   whose entire purpose is coverage.

2. **A committed baseline with two mechanisms and a mandatory reason.**
   `rules` are human-authored globs over id / path / message — drift-tolerant,
   so they survive line shifts and rewording. `fingerprints` are
   machine-generated content hashes — deliberately brittle, so editing the
   source reactivates the finding. Either way, "suppressed findings never count
   toward the risk score or active finding count. They remain in [output]
   marked with an external suppression for auditability." NVIDIA's own guidance
   is to prefer exact fingerprints for individually accepted findings and to
   reserve broad rules for deliberate policy exclusions, because "a broad rule
   can hide newly malicious content." This is what makes a re-review surface
   only what is new without losing what was accepted.

3. **The score is a prior; the verdict is a judgement.** SkillSpector publishes
   a posture table — e.g. "36-50 → manual review required; default to `CAUTION`
   unless every concern is explained" — kept explicitly separate from the raw
   score, and pairs it with a guardrail against the dominant failure mode of
   high-recall review, talking findings away: "Never downgrade unexplained HIGH
   or CRITICAL findings based only on reputation, score, or package name."

4. **Grounded findings.** Content is fed to the passes line-numbered
   (`L100: def foo()`) so a reported line is *copied*, not counted — this
   removes the "real bug, wrong line" false positive, which reads to an author
   exactly like a hallucination. Findings come back as a struct with at least
   severity, confidence, start_line, explanation and remediation; requiring
   `remediation` **at emission time** is a cheap, deterministic filter for
   findings nobody can act on. Confidence is normalized defensively in code
   (a model emitting `75` and one emitting `0.75` mean the same thing) rather
   than interpreted by eye.

5. **A report format that adjudicates.** A three-valued verdict —
   `APPROVE` / `CAUTION` / `REJECT` — where `CAUTION` exists precisely for
   behavior that is "documented, necessary, bounded, and controllable", so a
   reviewer never rounds a real concern to "fine" for want of a label. Every
   finding carries a *review judgment* — an explicit why-acceptable /
   why-suspicious / why-rejecting adjudication, not just a description. The
   report closes with **Guardrails**: the conditions under which the verdict
   holds. And it reports **degraded mode** honestly — "State clearly that no
   [scan] ran, then give a semantic-only verdict with lower confidence" /
   "Record that the static line was incomplete." Style: "a concise triage
   report, not a raw scanner dump"; specific evidence over generic advice;
   omit empty sections.

**Where we deliberately diverge — read this before citing NVIDIA at us.**
SkillSpector's *default* is the opposite of ours: its analyzer base instructs
the LLM to "prefer empty findings", to "avoid false positives" because "it is
better to miss an edge case than to report a speculative issue", and to report
only what it is confident about. That is precision-over-recall; jjstack
`/review` is recall-over-precision by design. What transfers is not NVIDIA's
default but their **architecture** — deterministic breadth feeding an
enrich-only LLM pass, with removal handled by an auditable, human-authored
baseline rather than by model judgement. That architecture is what makes high
recall survivable, and it is strictly more useful to us than to them. NVIDIA
even anticipates the inversion: "If a future analyzer specifically needs
high-recall behavior (flag everything, filter later), it should override
`build_prompt()` and omit the guidelines." Two further divergences are ours,
not theirs: we show suppressed findings by default (they hide them behind
`--show-suppressed`), and our posture table keys on the active-finding severity
profile rather than a synthesized 0–100 risk number, which our inputs do not
support.

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

- [NVIDIA/SkillSpector (repo)](https://github.com/NVIDIA/SkillSpector) — the deterministic-breadth + enrich-only-LLM architecture as a whole.
- [SkillSpector `skill-inspector` SKILL.md](https://raw.githubusercontent.com/NVIDIA/SkillSpector/main/skills/skill-inspector/SKILL.md) — the three-valued `APPROVE`/`CAUTION`/`REJECT` verdict, the score→posture table, the "never downgrade unexplained HIGH/CRITICAL on reputation" guardrail, the Review-judgment column, the Guardrails section, the degraded-mode instruction, and the "concise triage report, not a raw scanner dump" style rules.
- [SkillSpector `docs/SUPPRESSION.md`](https://raw.githubusercontent.com/NVIDIA/SkillSpector/main/docs/SUPPRESSION.md) — the committed baseline: drift-tolerant `rules` vs brittle `fingerprints`, the mandatory `reason`, "suppressed findings never count toward the risk score… remain marked for auditability", and the prefer-fingerprints guidance.
- [SkillSpector `docs/LLM_ANALYZER_BASE_GUIDE.md`](https://raw.githubusercontent.com/NVIDIA/SkillSpector/main/docs/LLM_ANALYZER_BASE_GUIDE.md) — line-numbered prompts (`L1:` prefixes) for grounded locations, the per-finding struct, and the explicit precision-over-recall default we invert.
- [SkillSpector `nodes/meta_analyzer.py`](https://raw.githubusercontent.com/NVIDIA/SkillSpector/main/src/skillspector/nodes/meta_analyzer.py) — `apply_filter`'s enrich-without-suppressing contract, the `llm-unconfirmed` annotation tag, the fail-closed passthrough on LLM failure, and the defensive 0-100 → 0.0-1.0 confidence validator.
- (Accuracy note: NVIDIA's public `NVIDIA/skills` repo has no code-review skill. SkillSpector reviews *skills as artifacts*; only its review mechanics are borrowed here.)
- [Anthropic claude-code-security-review — prompts.py](https://github.com/anthropics/claude-code-security-review/blob/main/claudecode/prompts.py) — primary: confidence tiers, exploit-scenario field, HIGH/MEDIUM gating, exclusion list.
- [anthropics/claude-code-security-review (repo)](https://github.com/anthropics/claude-code-security-review) — multi-agent narrow-scope + high-confidence framing.
- Anthropic `/code-review` plugin (`claude-plugins-official/code-review`) — the 5-pass fan-out + 0–100 confidence rubric + <80 filter analyzed above (inspected locally).
- [Google eng-practices — what to look for in a review](https://google.github.io/eng-practices/review/reviewer/looking-for.html) — canonical review dimensions; the `Nit:` convention.
- [Augment — deep code review: recall vs precision](https://www.augmentcode.com/guides/deep-code-review-recall-vs-precision) — precision/recall economics, repo-context multi-pass, learning from dismissals.
- [Propel — reducing AI review false positives](https://www.propelcode.ai/blog/ai-code-review-false-positives-reducing-noise) — nit/concern/must-fix labels, dismissal learning, suppression, policy-first.
- [CodeAnt — how many false positives are too many](https://www.codeant.ai/blogs/ai-code-review-false-positives) — per-category FP tolerances; alert-fatigue signal loss.
- [Pickuma — CodeRabbit vs Greptile vs Diamond 2026](https://pickuma.com/for-dev/ai-code-review-tools-coderabbit-greptile-diamond-2026/) — vendor positions on the precision/recall curve.
