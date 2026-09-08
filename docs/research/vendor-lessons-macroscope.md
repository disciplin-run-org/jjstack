# Vendor lessons — Macroscope (AI code review)

What jjstack `/review` took from [Macroscope](https://macroscope.com), what it
refused, and why. Companion to `references/code-review-best-practices.md`, kept
separate so vendor research stays auditable as vendor research: a claim's source
matters as much as its content, and a marketing claim folded into the operating
manual becomes indistinguishable from a sourced practice six months later.

Researched 2026-09-07 against public material only.

## State of the evidence — read this before believing anything below

Public material on Macroscope is **plentiful but almost entirely self-published.**
The company maintains a large SEO content farm under `macroscope.com/content/`
and `macroscope.com/comparison/` whose pages are written by the vendor and
consistently conclude that the vendor wins — including the "Macroscope vs
Greptile" and "Best Greptile Alternatives" pages that a search for an impartial
comparison surfaces first. Genuinely independent evaluation is **thin to absent**:
no Hacker News launch discussion was found, and the only non-vendor commentary
located was DeepSource's observation that
[every AI code review vendor benchmarks itself and wins](https://deepsource.com/blog/ai-code-review-benchmarks),
plus references to the
[Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark)
as the nearest thing to a neutral yardstick.

So: the *mechanics* below are reasonably well-attested (the vendor describes its
own architecture, and one third party corroborates one of them). The
*performance claims* are not independently verified by anyone, and the flagship
comparative claim collapses on inspection of the vendor's own methodology page.
Treated accordingly.

Macroscope's founders are Kayvon Beykpour and Joe Bernstein (Periscope) with Rob
Bishop (Magic Pony) — relevant only as context for why a young product has this
much published surface.

## The claimed mechanics

### 1. AST codewalkers building a reference graph — VERIFIABLE AS A DESCRIPTION

Macroscope says it runs "dedicated AST codewalkers" that "build a reference graph
for lower-latency reviews" for ten languages (Go, Python, TypeScript, JavaScript,
Vue, Java, Rust, Kotlin, Swift, Ruby), falling back to an "agentic analysis engine
with full cross-file codebase context" for everything else
([docs](https://docs.macroscope.com/bug-detection-and-fixes)). The stated payoff
is catching "bugs that span files, functions and services, which is the class of
bug a linter structurally cannot see" — tracing how a change to one function
affects callers elsewhere, whether a renamed method is handled at every reference,
whether a new path has test coverage
([product page](https://macroscope.com/ai-code-review)).

This is a real architectural description, not a slogan, and it names a real gap.
It is also the pointed part of the Greptile contrast: **AST reference graph
(precomputed, exhaustive) versus agentic search over an indexed code graph
(sampled, best-effort).** An agentic searcher finds callers it thinks to look for;
a reference graph enumerates them. That distinction is genuine and it is the one
thing here worth engineering around.

Unverifiable: whether their graph actually delivers this. No one outside the
company has tested it.

### 2. Reachability as a false-positive control — VERIFIABLE AS A MECHANIC

They claim the graph lets them "tell whether a suspicious line is actually
reachable," which is how they avoid "noisy false positives"
([product page](https://macroscope.com/ai-code-review)). Mechanically coherent and
a real technique. Note what it is: noise control by **adding evidence**, not by
dropping a check — the same shape as our Phase 5. It is the one noise-control
idea here that is philosophically compatible with a recall-first reviewer.

### 3. Live documentation lookup for third-party APIs — VERIFIABLE, AND CORROBORATED

The best-attested mechanic in the whole body of material, and the only one with
third-party confirmation. Macroscope queries live documentation during review
instead of relying on the model's training data, because LLMs "flag false
positives, falsely identifying issues that are actually correct according to
current documentation." Integrating Parallel's search API produced a **55%
reduction in review comments involving third-party libraries**
([Parallel case study](https://parallel.ai/blog/case-study-macroscope)); their
changelog independently dates web-research capability to Oct 2025
([changelog](https://docs.macroscope.com/changelog)).

The 55% is still a vendor-adjacent number (Parallel is the supplier being
promoted). But the *failure class* is real, obvious, and something every model-
driven reviewer suffers: the reviewer's knowledge of a library is frozen at
training time, the library moved, and correct code gets flagged. That does not
require anyone's benchmark to believe.

### 4. Beyond per-PR review — REAL PRODUCT SURFACE, WRONG ALTITUDE FOR US

"Status" (executive summaries, weekly digests, productivity dashboards), a Slack
agent for querying the codebase and git log, ticket-linkage that evaluates a PR
against its linked Jira/Linear issue, and Murmur (cloud agents writing code in
sandboxes). These genuinely operate above a single diff. They are also an
organisational-analytics SaaS surface, not a reviewer mechanic.

### 5. Operational controls — REAL, AND MOSTLY POINTED THE OTHER WAY

From the [changelog](https://docs.macroscope.com/changelog): four detection modes
(Budget / Balanced / Precise / Ultra) trading "recall, precision, latency and
cost"; minimum-severity filtering; `.macroscope/ignore.md` glob exclusions;
size-based file skipping; ~40% of PRs auto-approved; a four-tier severity model
(CRITICAL data loss/security breach → HIGH crashes → MEDIUM recoverable breakage
→ LOW cosmetic).

One control here is worth noting as *convergent evidence rather than a new idea*:
low-confidence findings are hidden but expandable, so a team can see "which
comments Macroscope considered leaving." That is our `Unconfirmed` and
`Demoted (prior decision)` sections, arrived at independently. No change needed;
it is reassurance that keeping a doubted finding visible-but-ranked-down is a
sound design and not an indulgence.

*(This originally pointed at a 40–59 confidence tier that no longer exists. It
was removed when verification became enrich-only: a finding is no longer scored
into a band, it is confirmed, tagged unconfirmed, demoted by prior decision, or
retired through the committed baseline. The guard in `test/smoke.sh` that caught
this stale pointer matches a bare word deliberately, so a rephrasing cannot dodge
it — including this note, which is why it is worded the way it is.)*

## The claims against Greptile — and why the headline does not survive

Macroscope's flagship comparative claim is **"catches 2X more bugs than Greptile"**
plus "4X less noise than the next closest"
([comparison page](https://macroscope.com/comparison/macroscope-vs-greptile)),
resting on their
[September 2025 benchmark](https://macroscope.com/blog/code-review-benchmark):
118 runtime bugs mined from 45 open-source repos across 8 languages, bug-fix
commits classified by an LLM, only self-contained runtime bugs retained,
git-blame used to attribute the introducing commit, a subset manually validated.

Reported detection: Macroscope 48.31% (57/118), CodeRabbit 45.76% (54/118),
Cursor Bugbot 42.37% (50/118), Greptile 23.61% (**17/72**), Graphite Diamond
18.26% (21/115).

**Look at Greptile's denominator.** Greptile was scored on 72 bugs, not 118 — and
the methodology section says why, plainly: *"Due to issues with rate limits and
availability, we were not able to have a consistent sample size of bugs across all
tools... Most notably, our access to Greptile's code review functionality was
disabled midway through our evaluation."* The vendor's own page therefore
establishes that **the "2X more bugs than Greptile" headline compares runs on
different, non-equivalent samples of a benchmark the claimant designed, against a
competitor whose access was cut off mid-evaluation.** The number cannot support
the claim. Credit where due: they disclosed it. The marketing page repeating the
headline does not.

The same page discloses two further limitations that undercut it: *"It is possible
that we were invisibly rate-limited by some of these tools"*, and — decisively —
that Macroscope had the opportunity to fix bugs surfaced during development while
*"the other tools we evaluated did not have the same opportunity."* That is
train-on-test contamination described in the vendor's own words.

Their noise claim is weaker still. "4X less noise" rests on **average comments per
PR** (Macroscope 2.55, CodeRabbit 10.84, Graphite Diamond 0.62) with the explicit
admission: *"We did not assess the quality, value or correctness of all of these
comments."* Comment count is not noise; it is volume. Only five non-matches per
tool were manually checked. By this metric Graphite Diamond — the worst detector
in their own table — is four times quieter than Macroscope, which shows exactly
what the metric measures.

**Is the underlying deficiency real?** Partly, and independently of Macroscope.
Greptile self-reports ~82% recall while third-party re-evaluation reportedly lands
nearer 45%, and independent testing has found Greptile noisier than peers. So
"Greptile's published recall is optimistic" is plausible on evidence that is not
Macroscope's. "Macroscope is 2X better" is not established by anything.

## What jjstack adopted

Two mechanics, both implemented as deterministic scripts because the mechanical
half genuinely is mechanical, wired into `/review` as **Phase 4.5**.

### Adopted 1 — cross-file blast radius (`bin/jjstack-review-blast-radius`)

Answers mechanic (1) without pretending to own an AST index. Every reviewer in
this stack reads the diff, which is right for scope and wrong for exactly one bug
class: **the caller that was not updated.** Change a signature, a return
contract, a nullability or an error behaviour, and the defect is not in the diff —
it is in files the diff never touched, structurally outside a diff-scoped
reviewer's frame.

The script scans the diff for changed *definitions*, censuses every file in the
repo referencing each symbol, and splits referrers into in-diff and NOT-in-diff.
The NOT-in-diff list is the output that matters — it hands the review a bounded
list of places to look that it would otherwise never open. Word-boundary
fixed-string matching, a stoplist and length floor keep a generic name from
censusing the whole repo.

It is a **recall instrument, not a filter**: it decides nothing and suppresses
nothing. That is the deliberate divergence from Macroscope, who use their graph
primarily to *reduce* output. We use the same signal to widen the net, then let
Phase 5 do the filtering — consistent with this skill's thesis that noise is
controlled by verification, never by dropping coverage.

We take the observable behaviour, not the machinery. A grep census is weaker than
a real reference graph: no type resolution, no dynamic dispatch, false hits on
same-named symbols in unrelated scopes. That is acceptable because the output is
read by a reviewer who checks it, not by a gate that acts on it.

### Adopted 2 — dependency inventory for stale-API findings (`bin/jjstack-review-dep-inventory`)

Answers mechanic (3), the best-evidenced item in the research. The lookup needs
judgment; knowing **which library at which version** does not — it is written down
in the repo's manifests. The script parses them deterministically (npm, pypi via
requirements + pyproject, go, cargo, rubygems, maven), skips vendored trees and
lockfiles, and prints the versions this repo actually pins.

Phase 4.5 then requires that any finding asserting a third-party API is misused
be checked against *that* version — via WebSearch on the real docs — before it
can be scored in Phase 5. A finding that contradicts current documentation for
the pinned version is dropped as a stale-knowledge false positive and named as
such.

This is the rare noise control that costs no recall at all: it removes findings
that are *wrong*, not findings that are *low-priority*. Nothing about it requires
believing any Macroscope benchmark.

## What jjstack rejected, and why

- **"2X more bugs than Greptile."** Rejected as evidence. The vendor's own
  methodology page discloses non-equivalent sample sizes (17/72 vs 57/118) caused
  by Greptile's access being disabled mid-evaluation, plus the admission that
  Macroscope alone could fix bugs found in the dataset during development. A
  self-designed benchmark with a contaminated training loop and a truncated
  competitor run establishes nothing comparative.
- **"98% precision" (up from 75%), "3.5x more bugs", "4X less noise", "40% of PRs
  auto-approved".** Rejected as unfalsifiable marketing: internal benchmarks, no
  published dataset, no methodology, no independent replication. Precision figures
  are meaningless without the recall they were traded against and the sample they
  were measured on.
- **Comment volume as a noise metric.** Rejected outright, and it is the claim
  most hostile to this skill. They concede they did not assess comment quality;
  in their own table the weakest detector is the quietest tool. Optimising for
  fewer comments is optimising for the appearance of precision. `/review` is
  explicitly built to emit *more* and then verify.
- **Detection-mode tiers (Budget / Balanced / Precise / Ultra).** Rejected: a cost
  dial that buys latency by giving up recall. jjstack `/review` is permanently the
  deepest setting — that is its entire reason to exist, and a project wanting
  cheap has gstack `/review`. Depth is already tunable via `ADVERSARIAL_PASSES`.
- **Minimum-severity filtering, `.macroscope/ignore.md` exclusions, size-based
  file skipping.** Rejected: control noise by dropping whole dimensions, files
  and severity bands before anything is examined — precisely the trade this skill
  was built to invert. Our exclusions (linter-catchable, style, pre-existing,
  unquotable) drop findings on their *merits* after examination, never sight-unseen
  by glob.
- **Auto-approval of ~40% of PRs.** Rejected as anti-thesis. A merge-throughput
  feature for a PR bot. `/review` is invoked deliberately before a merge that
  matters; a reviewer that can approve without reporting is not the deepest pass
  in the stack.
- **Status dashboards, productivity analytics, Slack digests, Murmur.** Not
  rejected on merit — genuinely a different and interesting altitude — but out of
  scope for a local pre-landing review skill. Team-level change intelligence is a
  hosted-service shape; there is no diff for it to act on.
- **Ticket-linkage / PR-versus-linked-issue conformance.** Not adopted *here*,
  deliberately: jjstack already answers spec conformance with `/two-stage-review`
  (spec compliance, then quality) and `/spec`. Folding it into `/review` would
  duplicate an existing skill rather than add coverage.

## Sources

- [Macroscope — product / AI code review](https://macroscope.com/ai-code-review) — AST reference graph, reachability, cross-file bug class, auto-approval, ticket context. Vendor.
- [Macroscope docs — Code Review](https://docs.macroscope.com/bug-detection-and-fixes) — codewalker language list, agentic fallback, severity tiers, detection modes. Vendor.
- [Macroscope — code review benchmark](https://macroscope.com/blog/code-review-benchmark) — the 118-bug dataset, per-tool detection rates, and the methodology disclosures that sink the headline claim. Vendor, but self-incriminating.
- [Macroscope vs Greptile comparison](https://macroscope.com/comparison/macroscope-vs-greptile) — the "2X more bugs" / "4X less noise" claims. Vendor marketing.
- [Macroscope — v3 Code Review](https://macroscope.com/blog/code-review-v3) — "auto-tune" prompt/model selection, 98% precision, nitpick reduction. Vendor, unfalsifiable.
- [Macroscope docs — changelog](https://docs.macroscope.com/changelog) — web research (Oct 2025), filtered-issues visibility, ignore files, minimum severity, detection modes. Vendor, but dated and specific.
- [Parallel — how Macroscope reduced code review false positives](https://parallel.ai/blog/case-study-macroscope) — the live-documentation-lookup mechanic and the 55% figure. Third party, though a supplier with an interest.
- [DeepSource — every AI code review vendor benchmarks itself, and wins](https://deepsource.com/blog/ai-code-review-benchmarks) — the structural reason to distrust every number on this page. Independent.
- [Martian Code Review Bench](https://github.com/withmartian/code-review-benchmark) — the nearest available neutral benchmark. Independent.
