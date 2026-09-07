# Vendor lessons — Aikido Security (scanner-first AI review)

Prior art for the jjstack `/review` thesis. `/review` already concluded that the
right shape is **deterministic breadth feeding an LLM pass that enriches rather
than suppresses**. Aikido Security is a commercial product built around exactly
that scanner+LLM split — but it comes from the security-scanning world
(SAST/DAST/SCA/secrets/IaC/container/CSPM) rather than the code-review world, so
its ground truth is *"can an attacker reach this"* where Greptile's is *"would a
human reviewer have commented on this."* That difference is the interesting part.

This file records what was **adopted**, what was **rejected**, and what belongs
in `/security-review` instead. Everything is labelled **[MECHANIC]** (a described
procedure you could reimplement or test) or **[MARKETING]** (a superlative or a
number with no published method). Be skeptical: Aikido publishes four mutually
inconsistent false-positive-reduction numbers on a single page, and disowns all
of them on its own agent-facing page.

## The one mechanic worth stealing: a documented three-stage pipeline

Aikido documents its SAST ordering explicitly, and the ordering is the whole
point **[MECHANIC]**:

> "The order is important: 1. **Reachability first.** A reachability engine
> checks whether the candidate vulnerable code path is actually reachable from an
> entry point, whether sanitization exists between source and sink, and whether
> the path lives in unused code. 2. **Reasoning models for the complex
> remainder.** For cases where reachability alone cannot rule a finding in or
> out, reasoning models evaluate the surrounding code context.
> 3. **Severity adjustment.** Baseline severity is re-scored up or down based on
> the context the previous two stages produced."

Three things in that are directly transferable:

1. **Deterministic first, model on the residue.** The expensive, non-deterministic
   stage runs only on what the cheap deterministic stage could not decide. This is
   the "algorithm first, inference last" rule arriving from the other direction.
2. **Severity adjustment is its own stage, and it moves in BOTH directions.**
   Aikido re-scores "up or down". jjstack's Phase 5 only ever gates *down* —
   context can demote a finding but nothing promotes one. Worth noting as a real
   gap in our design, even though this PR does not change Phase 5.
3. **Context signals annotate; they do not by themselves delete.** Reachability
   and exposure are inputs to a *score*, not a delete key.

Their triage layer is described the same way — AutoTriage "checks exploitability,
reads real code context, and **reprioritizes** issues" **[MECHANIC]**. The verb is
*reprioritize*, and dedup + reason-coded ignore states are platform mechanics
underneath it. That is the accountable half of the model, and it is what
`bin/jjstack-review-triage` implements.

## Adopted into `/review`

- **A finding is never deleted, only dispositioned with a recorded reason.**
  Scanner platforms cannot make a finding vanish — it moves to an ignored/snoozed
  state carrying a reason, and it stays inspectable. `/review`'s Phase 5 used to
  delete its `< 40` band outright, which makes a reviewer that looked and
  dismissed indistinguishable from one that never looked. Phase 5.7 now files
  every finding with a `disposition` + `reason` from a closed vocabulary, and the
  script exits 4 rather than render a ledger with an unexplained drop.
- **Reachability deprioritises; it never deletes.** Adopted as a *hard rule*,
  which is stronger than Aikido's own behaviour (see the rejected list). Encoded
  as: reason `not-reachable` is legal only with `defer` or `appendix`.
- **Deduplication across independent detectors.** Aikido dedups findings across
  its scanner fleet. `/review` runs 8+ independent lenses that will happily
  report the same defect three times. Ours collapses on a location+claim
  fingerprint — and keeps a **corroboration count**, because three lenses
  independently agreeing is a ranking signal. (The count is our extension, not
  Aikido's.)
- **Exposure classification as a blast-radius annotation.** Aikido's "is this
  actually shipped to production / is it a dev dependency" question, translated to
  code review as a deterministic path class: `prod` / `test` / `fixture` /
  `vendor` / `generated` / `docs`. It annotates and warns; it never filters.
  Notably this is a *fix* for an observed Aikido failure, not a copy of a success:
  practitioners on Hacker News report Aikido's PR review "alerts on test
  fixtures" and flags code "in isolation, without looking at the context" — the
  exact failure its own marketing accuses diff-only reviewers of.

## Rejected

- **[MARKETING] "AI code review that catches more bugs."** No benchmark, no
  comparator, no dataset. Aikido does not appear in Martian's Code Review Bench
  (~200k+ real PRs, 17–19 tools) at all. Nothing to adopt.
- **[MARKETING] "85% / 90% / 92% / ~95% fewer false positives."** Four different
  numbers on one page, none with a denominator, baseline, or method. Aikido's own
  agent-facing page states it "does not claim… a specific false-positive
  reduction number". A vendor that disowns its own marketing numbers has given
  you permission to ignore them.
- **[MARKETING] "Reads your whole codebase, not just a diff"** as a differentiator
  against Greptile — Greptile's founding architecture is a whole-repo graph index.
  The claim implies a distinction that does not exist.
- **[MARKETING] "Battle Hardened" vs Greptile's "Newly Released."** Adjectives.
- **[REJECTED MECHANIC] Letting the reasoning model close a deterministic
  finding.** Aikido's stage 2 does exactly this — reasoning models "identify and
  filter out false positives that reachability missed", and the only quantified
  support offered is a *relative* internal A/B ("roughly twice as many false
  positives on those complex cases compared to non-reasoning approaches") with no
  absolute baseline. The one public benchmark touching Aikido — run by a
  competitor, so read it skeptically, n=47 on a deliberately-vulnerable repo —
  scores it **86.67% precision but 27.66% recall, missing 34 of 47 issues**. That
  shape (quiet because it reports little) is consistent with the independent user
  reports, and it is the exact trade `/review` exists to refuse. So we take the
  reason-coded demotion and reject the deletion: an LLM here may demote a finding
  into the appendix or the suppressed section, never out of the ledger.
- **[POOR FIT] "Learns patterns from previous PRs."** Claimed by Aikido,
  undocumented in its help docs (which describe a human pasting extra context);
  Greptile documents the equivalent concretely. Nothing reimplementable, and
  jjstack's cross-session memory already owns this ground.

## Flagged for `/security-review`, deliberately NOT put in `/review`

`/review` is the general pre-landing reviewer; `/security-review` is the 10-phase
security audit. The genuinely security-shaped Aikido mechanics belong there:

- **Dependency/CVE reachability and exploitability** — "inspects how a vulnerable
  package is used in your repository or container" to decide whether a CVE is
  exploitable *here*. That is SCA, and `/security-review` already owns supply-chain
  risk (its §6.7).
- **Exploitability-weighted severity (CVSS + EPSS + exposure)** as a scoring model
  for vulnerabilities.
- **Container image, IaC, secrets and cloud-misconfiguration scanning** — Aikido's
  real defensible advantage over a PR reviewer, and entirely outside `/review`'s
  scope. `/security-review` already covers secrets (§6.3) and insecure defaults
  (§6.5).
- **Malware/typosquat detection in dependencies** — supply chain, not code review.

## Sources

- [Aikido SAST engine depth (agent-facing)](https://llms.aikidosecurity.com/aikido-sast-engine-depth) — primary: the three-stage reachability → reasoning → severity-adjustment ordering, and the page's own claim restrictions.
- [Aikido help — how Aikido uses AI](https://help.aikido.dev/ai-and-dev-tools/how-aikido-uses-ai) — AutoTriage "checks exploitability, reads real code context, and reprioritizes issues"; CVE exploitability inspects package usage.
- [Aikido vs Greptile](https://www.aikido.dev/comparison/aikido-vs-greptile) — the competitive claims, the feature matrix, and the self-contradicting org counts.
- [Aikido SAST product page](https://www.aikido.dev/code/static-code-analysis-sast) — the four inconsistent false-positive-reduction numbers.
- [Corgea vs Aikido benchmark](https://corgea.com/blog/corgea-vs-aikido-security-benchmark) — competitor-run, n=47: Aikido 86.67% precision / 27.66% recall / 34 false negatives.
- [Konvu — Aikido vs Snyk](https://konvu.com/compare/aikido-vs-snyk) — "Not one of those four figures comes with a denominator or a published method."
- [Hacker News — Aikido Code Audit thread](https://news.ycombinator.com/item?id=48604741) — practitioners: "alerts on code that only looks possibly vulnerable in isolation, without looking at the context"; "Alerts on test fixtures".
- [AWS Marketplace — Aikido reviews](https://aws.amazon.com/marketplace/reviews/reviews-list/prodview-cogk44gx2w4ge) — alert-volume overwhelm; "the suggested fix lacks detail".
- [Greptile — memory and learning](https://www.greptile.com/docs/how-greptile-works/memory-and-learning) — the documented learn-from-PR-comments loop Aikido claims but does not describe.
- [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark) — the independent leaderboard Aikido is absent from.
- [DeepSource — AI code review benchmarks](https://deepsource.com/blog/ai-code-review-benchmarks) — "Each vendor runs their own benchmark, on their own dataset, and wins."
