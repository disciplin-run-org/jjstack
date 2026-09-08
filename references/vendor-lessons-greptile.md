# Vendor lessons — Greptile

What the jjstack `/review` wrapper takes from Greptile's AI code reviewer, what
it refuses, and why. Companion to `references/code-review-best-practices.md`,
which stays the general operating manual; this file is scoped to one vendor so
the borrowing is auditable and the marketing is separated from the mechanics.

Greptile is worth studying because it sits at the opposite end of the same
curve we do. It is the loudest "we catch more bugs" reviewer on the market,
which makes it the most useful vendor to mine for a recall-first stack — and
the most important one to read sceptically, because a recall pitch is exactly
the pitch that can be won by commenting on everything.

**The one-line verdict:** their repo-wide context is a real mechanic and we took
it. Their noise control is a strictness dial that drops whole comment
categories, and we rejected it, because dropping dimensions to buy quiet is the
precise trade this skill exists to invert.

---

## What is actually verifiable

Statements below are drawn from Greptile's own docs and architecture pages,
which are specific enough to check.

1. **A graph of the repo, plus chunk embeddings.** They index "directories,
   files, functions, classes, variables" with edges for "function calls,
   imports, dependencies, variable usage", and query three things at review
   time: dependencies, **usage locations** ("everywhere `foo()` is called"), and
   pattern consistency against similar functions. Their self-host architecture
   page corroborates the infrastructure — PostgreSQL holding "Code embeddings
   (via pgvector)", plus `indexer-chunker` and `indexer-summarizer` workers.
   **Caveat worth stating:** no page anywhere names tree-sitter, an AST, or a
   language server, so "graph" is under-specified — it is chunk-plus-embedding
   retrieval with LLM-written summaries and a call/import layer, not
   compiler-grade analysis. And **no page documents index freshness at all** —
   no reindex cadence, no staleness bound, no incremental-update mechanism.
2. **Blast radius as a named goal.** Their engineering blog describes tracing
   "the data flow… function calls" to find second-order effects. This is the
   real difference between repo-context review and diff-only review, and it is
   the thing worth stealing.
3. **Cross-repo context ("Repo Clusters").** Related repositories are cloned
   read-only at review time, capped at **7 repos per review** and **20 GB**.
   A real mechanic with published limits.
4. **A configuration surface with named defaults.** `strictness` defaults to
   `2` of 3; `commentTypes` defaults to `["logic","syntax","style"]`;
   `fileChangeLimit` skips large PRs; `.greptile/` (with `config.json`,
   `rules.md`, `files.json`) takes precedence over root `greptile.json`, which
   takes precedence over dashboard defaults. Settings override, rules
   accumulate. (Note for anyone porting: there is **no** `commentThreshold`
   field — the knob is `strictness`.)
5. **Nitpick suppression with a protected list.** Comments are suppressed after
   being ignored roughly **3+ times**. Suppressible: style/formatting, import
   organisation, non-critical docs, naming, code organisation. **Never
   suppressed: security vulnerabilities, memory leaks, infinite loops, null
   pointer exceptions, missing input validation.** That exemption list is the
   single best idea on their site.
6. **A learning loop with named signals.** Team-to-team PR comments; replies to
   Greptile; **only 👍/👎 reactions count** ("Other emojis are treated as
   neutral"); and first-vs-last-commit diffing to detect whether a suggestion
   was actually implemented. Downvotes work better with a stated reason. Rules
   are also auto-inferred from observed behaviour.
7. **A per-repo knowledge base with a `Reverts` section** — "past high-signal
   revert/rollback/incident PRs" kept to enable "history-aware reviews".
8. **TREX — sandboxed code execution.** Per-issue subagents run in disposable
   sandboxes and emit "screenshots, logs, API traces, execution scripts", so a
   finding ships with artifacts a human can re-verify. This is their strongest
   genuine differentiator.
9. **Hybrid security.** Opengrep (a real OSS rule engine) plus SCA plus an AI
   agent for chained exploits — deterministic scanners first to "reduce the
   entropy of the search space".

## What is marketing

- **"Merge 4X Faster, Catch 3X More Bugs."** No cited study, and the "3X" does
  not even match their own published benchmark (82% vs 44%).
- **"Concise reviews", "maximizes signal-to-noise ratio".** Unfalsifiable:
  Greptile publishes **no false-positive rate and no precision figure anywhere**,
  and their own analytics product has no false-positive metric — it tracks
  "Addressed Rate" and upvote/downvote ratio instead. The two independent users
  who ran it head-to-head against CodeRabbit report the opposite direction on
  noise.
- **"9,078 'great catch' replies in 7 days".** A numerator with no denominator:
  it is not impressive if the tool made a million comments, and — as one
  commenter noted — in an agentic loop the praise may be coming from other bots.
  The lesson generalises: **any adoption metric without a comment-volume
  denominator is decoration.**
- **"Swarm of agents."** Parallel scoped subagents are real; "swarm" carries no
  published topology or count. Branding on top of a mechanic we already have.
- **"Greptile learns your codebase over time."** True in the trivial sense; the
  mechanic underneath is item 6 above. The phrase is not the feature.
- **"Learning reduces ignored comments by 80% and increases suggestion adoption
  threefold."** No methodology, no sample, no timeframe. The weakest-sourced
  number they publish.
- **"Independence" — a reviewer that "shares no codebase or scaffolding with the
  coding agent."** Structurally true, but the quality inference drawn from it is
  an assertion, not evidence.
- **No exclusions are ever published.** There is no "we are not a SAST tool" or
  "we don't do style" statement on their site. Every scope claim is an
  expansion. They do concede, once, that "Noise exists. False positives and
  overbroad suggestions happen."

## The numbers, and who measured them

Every figure Greptile publishes is measured by Greptile.

- **The headline benchmark** — Greptile 82%, Bugbot 58%, Copilot 54%,
  CodeRabbit 44%, Graphite 6% — is 50 reconstructed bug-fix PRs across five OSS
  repos, run on default settings. **Read the scoring rule before believing the
  ranking: it counts caught bugs "excluding false positives and style
  suggestions from scoring."** That measures *recall only*. A tool that comments
  on everything wins it. The vendor chose the dataset, ran the competitors, and
  defined the metric.
- **Their most credible data** is the v4 A/B test on production telemetry
  across "hundreds of thousands of PRs": comment address rate 30% → 43%,
  addressed comments per PR 0.92 → 1.60. Still a usefulness proxy, not a
  false-positive rate.
- **v5** claims "flags fewer false positives" **with no number attached**, and
  its address-rate baseline (52%) contradicts v4's (43%) with no explanation.
- TREX "20% more bugs caught in evals" and security "nearly 3x" are internal
  evals with undisclosed datasets.

**Conclusion:** Greptile has published good evidence that it has high recall and
**no evidence at all about its precision**. Which, read honestly, makes it a
close cousin of this skill — and means the interesting question is not "are they
better" but "what did they build to make high recall survivable".

## What outside voices say

The vendor's own numbers are all recall. The independent record is where the
precision story should be — and the most important finding is that **it does not
exist**. No trustworthy public false-positive number for Greptile could be
found. Every candidate fails on inspection:

- **Their own benchmark** excludes false positives from scoring by construction.
- **The Martian Code Review Bench**, the nearest thing to a neutral leaderboard,
  seeded its gold set partly from Greptile's own data — so Greptile is graded
  against an answer key it helped write — and the leaderboard is unstable enough
  that CodeRabbit, cubic, Qodo, Kilo and Greptile have each announced a #1
  finish from different snapshots. Any "#1 on the independent benchmark" claim
  is a date chosen by the claimant.
- **The best real field trial** (dev.to, 146 merged PRs over 3 weeks, dataset
  open-sourced) reports Greptile at **0% false positives** — but its verdicts
  are auto-labelled by reply prefix, so "0%" means nobody on that team ever
  typed `Not applicable:`. A 98% fix-through rate is an adoption convention, not
  an adjudication. The same trial credits Greptile with the fewest findings
  (120 vs CodeRabbit's 281), 40 P1s no other tool caught, and roughly half
  CodeRabbit's latency — those are the credible parts.
- **The widely-quoted "11 false positives vs CodeRabbit's 2"** traces to a
  competing vendor's blog citing an unnamed "independent evaluation", and has
  since mutated from "per run" to "per PR" in republication. Do not use it.

Practitioner reports are sharply **bimodal**, not mixed-leaning-positive. The
recurring complaints, each from several independent accounts, are: nit volume
("pure noise… I ran it for 3 PRs and then gave up"), **missing local context it
claims to have** — flagging code whose invariant is established elsewhere in the
same file, which is a failure of the exact thing it sells — stale-world
hallucination (flagging a real Python version as nonexistent), sycophantic
capitulation when challenged, and vague architectural hand-waving. One
multi-week corporate evaluation ended in a *no* on those grounds. Against that,
several equally specific accounts report it catching real cross-file issues
other tools missed.

Three of those outside observations changed what we built:

1. **Their own founder's admission that LLM self-filtering failed.** Greptile
   published that "the LLM's judgment of its own output was nearly random" for
   nit-filtering, and shipped an embedding-KNN filter instead. That is a direct
   warning about Phase 5: a self-scored confidence number is a weak filter on
   its own. It is why our gate is not a bare score but a score **plus a quotable
   motivating line plus a concrete failure scenario** — three independent
   requirements, only one of which is self-assessment.
2. **The critique of confidence scores as actively harmful** — a reviewer sees
   a number and assumes something is wrong. This is why `Module G` forbids the
   ledger from touching a finding's confidence score: a demotion is a claim
   about the team's prior decision, and a score is a claim about the code.
   Conflating them corrupts both signals.
3. **The nit-filter pitfall Greptile themselves called "the biggest pitfall of
   this method"** — a learned suppressor can silence an entire class or module
   rather than a comment *form*. Our ledger cannot: matches are per
   path-glob **and** category, protected categories never demote, and the whole
   store is a diffable file rather than a learned weight nobody can inspect.

An honest note on category-level fatigue: in the "AI review is slop" threads,
Greptile and CodeRabbit are named interchangeably. Much of the criticism is
aimed at the category, not the vendor — and a recall-first reviewer like ours is
squarely in that category. Everything in `code-review-best-practices.md` about
alert fatigue applies to us at least as strongly as to them.

## What our own operational history says

gstack ships `~/.claude/skills/gstack/review/greptile-triage.md` — a whole
document for triaging Greptile's comments on our PRs. Its existence and shape
are the most direct evidence we have, and it implies three failure modes that
no vendor page mentions:

1. **False positives are frequent enough to need persistent state.** The doc
   maintains a per-project `greptile-history.md` of suppressions keyed by
   file-pattern and category. You do not build a suppression database for a
   tool that is usually right.
2. **The learning loop does not close inside a PR.** The doc has *escalation
   detection* and a two-tier reply ladder: Tier 1 friendly, Tier 2 "firm,
   overwhelming evidence" for when Greptile **re-flags something after being
   answered**. Whatever the 3-ignores suppression does over weeks, it does not
   stop repetition within a review.
3. **Severity is mis-ranked.** Every reply template carries a
   `**Suggested re-rank:**` field, because Greptile flags "style/noise/misread"
   issues as security or race-condition class. Inflated severity is its
   characteristic noise, not volume alone.

And one rule from that doc we adopted verbatim, because it is exactly right:
suppress only `type == fp` — **"only suppress known false positives, not
previously fixed real issues."** Suppressing a previously-fixed issue hides the
regression of a bug the repo has already paid for once.

---

## What we adopted, and where it lives

Each of these is a script, not a paragraph of prompt: indexing, matching,
counting and history search are mechanical, so they belong in tested code where
the model spends its judgment on the finding instead of on the grep.

| Greptile mechanic | Our implementation | What changed |
|---|---|---|
| Repo-wide context / "usage locations" / blast radius | `bin/jjstack-review-blast-radius` | For every identifier whose *definition* the diff touches, list every reference in files the diff did **not** touch. Exact rather than embedded: we need "who calls this", which grep answers precisely and for free. |
| Cross-repo context ("Repo Clusters") | `--also-repo` on the same script | Sibling repos are searched too, sites labelled `(reponame)`. A shared module's callers usually live in another repo. |
| Learning from dismissals | `bin/jjstack-review-ledger` | A per-repo dismissal ledger — **in the repo, in git, reviewable in a PR**, rather than on a vendor's server. |
| The never-suppress exemption list | `PROTECTED_CATS` in the ledger | security, correctness, concurrency, error-handling, resource-leak and test-coverage are recorded but **never demote**. The classes most in need of suppression pressure are the ones where a wrong suppression ships an incident. |
| "Only dismissals suppress" | ledger `--type` check | `fixed` and `confirmed` records are history, never suppression. Straight from `greptile-triage.md`. |
| Knowledge-base `Reverts` section | `bin/jjstack-review-revert-history` | Ask git which changed files have been reverted, rolled back or hotfixed before, and hand that to the git-history pass as a pre-computed input. |

**The one deliberate divergence.** Greptile's memory *suppresses*. Ours
**demotes**: a matched dismissal moves a finding into 5f's `Demoted (prior
decision)` section with the prior decision quoted, and never drops it — it keeps
its severity and confidence and only moves down the page. A recall-first
reviewer that silently
inherits every past wave-off becomes a precision-first reviewer without anyone
deciding to. Demotion keeps the finding visible and keeps the decision
re-litigable; deletion of a ledger line is a reviewable diff like any other.

## What we rejected, and why

- **`strictness` levels and `commentTypes` toggles.** Their noise control works
  by turning off whole classes of comment. That is the exact trade this skill
  inverts — we control noise by verifying findings (Phase 5), never by dropping
  a dimension. Rejected on stance, not on quality.
- **`fileChangeLimit` / skipping large PRs.** A big diff is where recall matters
  most. gstack's small-diff skip is already overridden in Phase 2 for the mirror
  image of this reason.
- **`autoApprove` on a 5/5 confidence review.** A reviewer that approves on its
  own read is not a reviewer. Out of scope for a pre-landing gate.
- **TREX-style sandboxed code execution.** The best thing they built, and the
  wrong thing for us. `/review` runs locally against a working tree; executing
  code from the diff under review, locally, is a security regression, and we
  have no disposable sandbox. We keep the *intent* — a finding must carry
  evidence — through Phase 5's mandatory concrete failure scenario, which is the
  cheap proxy for "prove it actually runs".
- **A hosted graph index with pgvector embeddings.** Infrastructure we do not
  need for the question we actually ask. Embedding retrieval is fuzzy by
  construction; "which files reference this symbol" is not a fuzzy question.
  Their own docs never establish AST-level analysis, so the fidelity gap we
  would be buying is unproven.
- **Their benchmark as evidence of anything comparative.** Vendor-run,
  vendor-chosen dataset, and scored with false positives explicitly excluded.
  We cite it only as evidence that they optimise recall.
- **"Model inversion"** (routing a review to a different model than the one that
  wrote the code). Structurally sensible and possibly the most interesting idea
  on their changelog, but it is a harness-level decision about which model runs
  the session — a skill cannot implement it. Noted, not adopted.
- **Cosmetic report features** — sequence diagrams, issues tables, confidence
  score sections. Presentation, not detection.

## Sources

All retrieved from public pages; Greptile mirrors most docs as `.md`.

- [Graph-based codebase context](https://www.greptile.com/docs/how-greptile-works/graph-based-codebase-context) — what is indexed; dependencies / usage locations / pattern consistency.
- [System architecture](https://www.greptile.com/docs/system-architecture) — pgvector embeddings, chunker and summarizer workers.
- [Introduction](https://www.greptile.com/docs/introduction) — "builds a graph of your entire repository"; the 2–3 week calibration claim.
- [Automating code validation (blog)](https://www.greptile.com/blog/automating-code-validation) — blast radius, second-order effects, cheap-model/frontier-model split.
- [Cross-repo context](https://www.greptile.com/docs/code-review/cross-repo-context) — Repo Clusters, 7-repo / 20 GB limits.
- [greptile.json reference](https://www.greptile.com/docs/code-review/greptile-json-reference) and [controlling nitpickiness](https://www.greptile.com/docs/code-review/controlling-nitpickiness) — `strictness` (default 2), `commentTypes`, `fileChangeLimit`, `autoApprove`.
- [Nitpicks](https://www.greptile.com/docs/how-greptile-works/nitpicks) — suppression after ~3 ignores; the never-suppress list.
- [Memory and learning](https://www.greptile.com/docs/how-greptile-works/memory-and-learning) and [training the learning system](https://www.greptile.com/docs/code-review/training-the-learning-system) — 👍/👎 only, reply signals, commit-diffing, the unsourced 80% / 3x claim.
- [Knowledge bases](https://www.greptile.com/docs/how-greptile-works/knowledge-bases) — the `Reverts` section and history-aware review.
- [TREX code execution (blog)](https://www.greptile.com/blog/trex-code-execution) — sandboxed per-issue agents, artifact sets, and their idiosyncratic redefinition of "precision" as run-to-run consistency.
- [Benchmarks](https://www.greptile.com/benchmarks) — the 82/58/54/44/6 table and the "excluding false positives… from scoring" rule.
- [Greptile v4 (blog)](https://www.greptile.com/blog/greptile-v4) — the A/B production telemetry.
- [Security check](https://www.greptile.com/security-check) — Opengrep + SCA + AI agent.
- [What is AI code review](https://www.greptile.com/what-is-ai-code-review) — their one concession that "Noise exists."
- [Make LLMs shut up (blog)](https://www.greptile.com/blog/make-llms-shut-up) — the admission that "the LLM's judgment of its own output was nearly random" for nit-filtering, and the embedding-KNN filter they shipped instead; the [HN thread](https://news.ycombinator.com/item?id=42451968) contains their own "biggest pitfall of this method" reply about class-level suppression.
- [HN 46777079](https://news.ycombinator.com/item?id=46777079) — the most detailed independent teardown: missed in-file context, a training-cutoff hallucination, sycophantic capitulation, and the argument that confidence scores mislead reviewers.
- [HN 46770441](https://news.ycombinator.com/item?id=46770441) — a multi-week corporate evaluation that ended in a decision not to buy.
- [HN 44786514](https://news.ycombinator.com/item?id=44786514) — the most balanced positive account ("overzealous, but more often than not catches real issues").
- [dev.to — 4 reviewers in parallel, 3 weeks, 146 PRs, 679 findings](https://dev.to/_vjk/best-ai-code-reviewer-in-2026-we-ran-4-in-parallel-for-3-weeks-146-prs-679-findings-1c0f) — the best independent field trial; dataset at [vlad-ko/pr-review-bench](https://github.com/vlad-ko/pr-review-bench). Read its labelling protocol before quoting the 0% FP figure.
- [Martian Code Review Bench](https://codereview.withmartian.com/) and [CodeAnt's analysis of its gold-set bias](https://www.codeant.ai/blogs/ai-code-review-benchmark-results-from-200-000-real-pull-requests) — why no vendor's "#1" claim on it settles anything.
- [PostHog engineering handbook — how we review](https://posthog.com/handbook/engineering/how-we-review) — a named customer's deliberately unenthusiastic scoping, including the anti-pile-on rule ("three agents arguing with each other is noisy").
- `~/.claude/skills/gstack/review/greptile-triage.md` — our own operational triage doc: per-project FP suppressions, Tier-1/Tier-2 escalation for re-flagged comments, and the `Suggested re-rank:` template for mis-ranked severity.
