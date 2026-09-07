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

Their help docs state the ordering even more plainly, under the heading "False
positive filtering before triage" **[MECHANIC]**:

> "**Before AutoTriage uses an LLM to look at your code**, Aikido's reachability
> engine filters out false positives by checking whether vulnerable code paths are
> even reachable in your application. […] If exploitability cannot be ruled out,
> then AutoTriage proceeds to prioritization."

Four things in that are directly transferable:

1. **Deterministic first, model on the residue.** The expensive, non-deterministic
   stage runs only on what the cheap deterministic stage could not decide. This is
   the "algorithm first, inference last" rule arriving from the other direction.
2. **The deterministic engine owns the DROP; the model owns the RANK.** This is
   the sharpest line in the whole product, and it is the one to copy. For SAST,
   the LLM's output is a *severity adjustment only* — it "starts from Aikido's
   severity score (0–100) and adjusts it up or down using the code context
   gathered in the earlier steps." Auto-ignoring is attributed to the
   non-LLM reachability logic, not to the model.
3. **Severity adjustment is its own stage, and it moves in BOTH directions.**
   jjstack's Phase 5 only ever gates *down* — context can demote a finding but
   nothing promotes one. A real gap in our design; noted, not fixed here, because
   Phase 5 is being rewritten in a concurrent PR.
4. **Uncertainty resolves toward keeping the finding.** Their stated failure-mode
   policy is the single best sentence on the site **[MECHANIC]**:

   > "Aikido's reachability engine uses a 'conservative **under-approximation**,'
   > so it only marks code as unreachable when it can be determined with high
   > confidence. […] In these ambiguous cases, Aikido errs on the side of caution:
   > **instead of suppressing a potentially relevant issue, it will either keep it
   > as-is or lower its severity.**"

   Suppression requires proof (`"only when the vulnerable symbol is provably
   unreachable"`); ambiguity buys a downgrade, never a delete. The secrets triager
   states the same rule independently: "When in doubt, Aikido keeps the finding so
   you can review it rather than hiding a real exposure."

Their triage layer is described the same way — AutoTriage "checks exploitability,
reads real code context, and **reprioritizes** issues" **[MECHANIC]**. The verb is
*reprioritize*. That is the accountable half of the model, and it is what
`bin/jjstack-review-triage` implements.

## Suppression as a reversible, typed, reason-carrying state

The reimplementable artifact is their SIEM export schema **[MECHANIC]**, which
makes the suppression reason a first-class machine-readable field:

> `ignore_reasons` | array | "Why the issue is ignored. Empty array if it isn't.
> Each entry has a `kind` (`manual_ignore`, `auto_ignore`, `rule_ignore`, or
> `api_ignore`) and a human-readable `reason`."

Three properties of that design are worth naming:

- **Suppressed findings move to a view, not to nothing.** "The ignore view
  consolidates all issues ignored by Aikido's triaging algorithm, as well as those
  manually ignored by users. Here, you can review the **rationale behind each
  automatically ignored issue**."
- **Suppression is reversible and continuously re-evaluated.** "If evidence changes
  (such as with a new import), the severity is automatically reevaluted." Turning
  off their EPSS rules "unignores" everything those rules had ignored — the
  suppression was a filter over the data, never a deletion of it.
- **The no-op is recorded.** Their secrets triager has an explicit
  "**Neutral: Assessment ran without changing priority**" verdict. That is exactly
  the distinction `/review` needed: *the triager looked and declined to act* is a
  different fact from *the triager never ran*, and only one of them is auditable
  if you record nothing.

**Not implemented here, worth considering later:** the `kind` provenance taxonomy.
Our ledger records *why* a finding was demoted but not *who decided* — a rule, a
model, or a human. Adding a provenance column would let a later reviewer discount
model-made suppressions specifically. Deliberately out of scope for this PR.

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
- **Deduplication across independent detectors.** `/review` runs 8+ independent
  lenses that will happily report the same defect three times. Ours collapses on a
  location+claim fingerprint and keeps a **corroboration count**, because three
  lenses independently agreeing is a ranking signal. *This one is ours, not
  theirs* — Aikido's marketing names a "deduplication and de-noising engine" but
  publishes no keys, normalization fields, or matching logic anywhere, so there
  was nothing to copy. **[MARKETING]** on their side; our design is independent.
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
- **[REJECTED MECHANIC] Letting a model close a finding on its own authority.**
  Read carefully, Aikido is *inconsistent across scanner classes* here, and only
  one of the three behaviours is worth copying:
  - **SAST — the model cannot suppress.** Its output is a severity delta; the
    deterministic engine owns the drop. **This is the good design, and we adopt
    it** (invariant 2 above).
  - **SCA — the agent can Downgrade/Upgrade/Snooze/Ignore, but each action is
    independently set to "Fully Automated" or "Human Approval"**, and applying a
    change is guarded by a compare-and-swap: "Severity changes only apply when the
    finding's current severity still matches what the agent analyzed." A defensible
    **[MECHANIC]**, and the permissioning is the reason it is defensible.
  - **Secrets — the agent auto-ignores outright** ("Auto-ignored: Finding removed
    from your feed as a false positive"). **This is the one we reject.**

  The only quantified support for model-driven suppression anywhere is a *relative*
  internal A/B ("roughly twice as many false positives on those complex cases") —
  and the backing blog post publishes no dataset, sample size, ground-truth
  procedure, or precision/recall, and its actual scoped claim covers **path
  traversal in JavaScript only** before being generalized in marketing copy.
  Meanwhile the one public benchmark touching Aikido — competitor-run, n=47, read
  skeptically — scores it **86.67% precision against 27.66% recall, missing 34 of
  47 issues**. Quiet because it reports little. That is the exact trade `/review`
  exists to refuse, so our rule is stricter than any of the three: a model here may
  demote a finding into the appendix or the suppressed section, never out of the
  ledger.
- **[REJECTED MECHANIC] A class-level "confidence" label presented as evidence
  about the instance.** Every SAST AutoFix carries a High/Medium/Low confidence
  that "reflects how strongly **benchmarking** suggests the generated change both
  fixes the vulnerability and preserves correct behavior" — i.e. a *prior over the
  rule class*, computed from an unpublished benchmark suite, not evidence about the
  patch in front of you. This is a live trap for us: `/review`'s own 0–100 score is
  only meaningful because Phase 5 requires a quoted line and a concrete failure
  scenario *for that specific finding*. A confidence number sourced from anything
  other than the instance is decoration.
- **[POOR FIT] "Learns patterns from previous PRs."** Claimed by Aikido,
  undocumented in its help docs (which describe a human pasting extra context);
  Greptile documents the equivalent concretely. Nothing reimplementable, and
  jjstack's cross-session memory already owns this ground.

## Their remediation story, and the gap in it

Worth knowing because `/review` proposes fixes too. Generation is a real
**[MECHANIC]**: "it gathers the relevant code context, formulates a remediation
plan, and then applies a minimal fix", with **per-rule prompt templates** rather
than one generic "fix this" prompt — "Each SAST AutoFix is tied to a particular
rule and remediation pattern."

But **a proposed fix is not validated before it is offered.** No test run, no
re-scan, no compile check gates the patch; their own docs concede "Manual reviews
before merging are recommended." The only re-scan documented is *post-apply*, in
the IDE ("Once applied, your code is automatically updated and rescanned to
confirm the issue is resolved") — a confirmation loop, not a gate. The single
exception is container base-image upgrades, where they do compute a differential
up front: AutoFix "surfaces which vulnerabilities would be remediated **and
whether any new ones would be introduced**."

The lesson for us is the container one, generalized: **if you propose a fix,
compute what it breaks before offering it, not after applying it.** Note this is
an argument for `/review` keeping its hands off remediation, not an argument for
adding an autofixer.

## Flagged for `/security-review`, deliberately NOT put in `/review`

`/review` is the general pre-landing reviewer; `/security-review` is the 10-phase
security audit. The genuinely security-shaped Aikido mechanics belong there:

- **Dependency/CVE reachability and exploitability** — "inspects how a vulnerable
  package is used in your repository or container" to decide whether a CVE is
  exploitable *here*. That is SCA, and `/security-review` already owns supply-chain
  risk (its §6.7).
- **Exploitability-weighted severity** — and they publish the actual arithmetic
  **[MECHANIC]**, which is rare enough to be worth copying wholesale: a 0–100 scale
  ("10× more granularity than traditional CVSS"), **+5** if on the CISA KEV
  catalog, **+1** for a public PoC on GitHub, **−5/−10** for low EPSS bands, and
  auto-ignore under EPSS 1% — with a documented **precedence guard**: the EPSS
  rules "only run when the CVE is not on KEV and has no public PoC," so a
  known-exploited CVE can never be quieted by a low score. Business context
  (internet exposure as a *three-valued* Yes/No/**Unknown**, data sensitivity,
  prod vs test) feeds the same number.
- **Score explainability** — every adjustment is individually attributable:
  "Click an issue's severity score to see which rules applied, including KEV, PoC,
  and EPSS adjustments." A severity that decomposes into named, inspectable deltas
  is strictly better than one asserted whole. Applies to `/security-review`'s
  scoring; a general reviewer has no equivalent public feed to weight against.
- **Container image, IaC, secrets and cloud-misconfiguration scanning** — Aikido's
  real defensible advantage over a PR reviewer, and entirely outside `/review`'s
  scope. `/security-review` already covers secrets (§6.3) and insecure defaults
  (§6.5).
- **Malware/typosquat detection in dependencies** — supply chain, not code review.

## Sources

- [Aikido SAST engine depth (agent-facing)](https://llms.aikidosecurity.com/aikido-sast-engine-depth) — primary: the three-stage reachability → reasoning → severity-adjustment ordering, and the page's own claim restrictions.
- [Aikido help — SAST AutoTriage](https://help.aikido.dev/aikido-agent/sast-autotriage.md) — primary: "Before AutoTriage uses an LLM to look at your code…"; the LLM adjusts severity, the reachability engine owns the drop.
- [Aikido help — reachability analysis](https://help.aikido.dev/getting-started/reachability-analysis/introduction-to-reachability-analysis.md) and [the false-positive engine](https://help.aikido.dev/getting-started/reachability-analysis/reachability-engine-to-remove-false-positives.md) — the conservative under-approximation policy, guarded downgrades, continuous re-evaluation.
- [Aikido help — SIEM field reference](https://help.aikido.dev/miscellaneous-integrations/siem-connectors/siem-field-reference.md) — the `ignore_reasons` schema with typed `kind` provenance. The reimplementable artifact.
- [Aikido help — secrets AutoTriage](https://help.aikido.dev/aikido-agent/secrets-autotriage.md) — "When in doubt, Aikido keeps the finding"; the explicit "Neutral: Assessment ran without changing priority" no-op record.
- [Aikido help — CVE exploitability analysis](https://help.aikido.dev/aikido-agent/cve-exploitability-analysis.md) — per-action "Fully Automated" vs "Human Approval", and the compare-and-swap on apply.
- [Aikido help — severity scoring](https://help.aikido.dev/getting-started/core-functionalities/how-is-severity-score-calculated.md) and [EPSS noise rules](https://help.aikido.dev/code-scanning/miscellaneous/use-epss-values-to-further-reduce-noise.md) — the published arithmetic and the KEV/PoC precedence guard.
- [Aikido help — AutoFix overview](https://help.aikido.dev/autofix-and-remediation/overview-aikido-autofix.md) — per-rule remediation templates; the class-level benchmark "confidence"; no pre-offer validation.
- [Aikido help — how Aikido uses AI](https://help.aikido.dev/ai-and-dev-tools/how-aikido-uses-ai) — AutoTriage "checks exploitability, reads real code context, and reprioritizes issues".
- [Aikido blog — reasoning models in AutoTriage](https://www.aikido.dev/blog/reasoning-models-autotriage) — the "twice as many false positives" claim; no dataset, sample size, or precision/recall published, and scoped to path traversal in JavaScript.
- [Aikido vs Greptile](https://www.aikido.dev/comparison/aikido-vs-greptile) — the competitive claims, the feature matrix, and the self-contradicting org counts.
- [Aikido SAST product page](https://www.aikido.dev/code/static-code-analysis-sast) — the four inconsistent false-positive-reduction numbers.
- [Corgea vs Aikido benchmark](https://corgea.com/blog/corgea-vs-aikido-security-benchmark) — competitor-run, n=47: Aikido 86.67% precision / 27.66% recall / 34 false negatives.
- [Konvu — Aikido vs Snyk](https://konvu.com/compare/aikido-vs-snyk) — "Not one of those four figures comes with a denominator or a published method."
- [Hacker News — Aikido Code Audit thread](https://news.ycombinator.com/item?id=48604741) — practitioners: "alerts on code that only looks possibly vulnerable in isolation, without looking at the context"; "Alerts on test fixtures".
- [AWS Marketplace — Aikido reviews](https://aws.amazon.com/marketplace/reviews/reviews-list/prodview-cogk44gx2w4ge) — alert-volume overwhelm; "the suggested fix lacks detail".
- [Greptile — memory and learning](https://www.greptile.com/docs/how-greptile-works/memory-and-learning) — the documented learn-from-PR-comments loop Aikido claims but does not describe.
- [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark) — the independent leaderboard Aikido is absent from.
- [DeepSource — AI code review benchmarks](https://deepsource.com/blog/ai-code-review-benchmarks) — "Each vendor runs their own benchmark, on their own dataset, and wins."
