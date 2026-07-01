# The "Competitor did it" pass — why it works

Shared rationale for the **Competitor-did-it** pass used by `/council` and
`/consensus`. The operational steps live inline in each skill (so neither breaks
if this note isn't read); this file holds the science once, so it isn't
duplicated as prose. Stable runtime path:
`~/.claude/skills/council/references/competitor-did-it.md`.

## What the pass is

When a panel concludes that something **can't be done / is impossible /
infeasible / blocked**, do not accept the verdict. Stipulate that a well-resourced
competitor has *already* solved it and ships in 30 days, and force every voice to
reconstruct the method. Self-imposed constraints fall out as the residue.

It is the purpose-built **inverse of the Tenth Man** and the constructive **twin
of the pre-mortem**:

| | fires on | charter | mode |
|---|---|---|---|
| Tenth Man | positive convergence ("yes, this works") | argue the consensus is WRONG | critique / destruction |
| Pre-mortem | risky/irreversible "yes" | assume it failed — why? | risk-hunting |
| **Competitor did it** | **negative verdict ("no / impossible")** | **a rival shipped it — how?** | **construction / invention** |

## Why a "no" deserves *more* scrutiny than a "yes"

**Clarke's First Law.** *"When a distinguished but elderly scientist states that
something is possible, he is almost certainly right. When he states that something
is impossible, he is very probably wrong."* The impossibility verdict is the
unreliable one — yet our other guards (Tenth Man, pre-mortem, disconfirmation) all
police the false *positive*. A false *no* sailed straight to synthesis unchallenged.

**It's a universal negative (Popper).** "Possible" needs a single example to
prove. "Impossible" must rule out *every* approach that exists or could exist —
the logically hardest claim to establish, asymmetrically falsifiable by one
counterexample. Yet panels assert it more casually than "possible," because "it
can't be done" wears the costume of rigor and humility, and it ends the
conversation as a stopper. The harder-to-justify claim gets the easier pass. That
inversion is exactly what this pass corrects.

## Why the competitor framing breaks the block

Three levers fire at once, each defeating a named failure mode:

1. **Epistemic → abductive flip (Peirce).** "Can this be done?" invites a
   *confidence judgment*, and "no" is the safe answer. "A rival did it — how?"
   invites *inference to the best explanation*. Reconstructing a hidden mechanism
   is generative where adjudicating possibility is merely evaluative; humans (and
   models) are far better at the former.
2. **Stipulated certainty removes the escape hatch.** Generic inversion ("imagine
   it's possible") still lets the panel answer "but it isn't." "It is done, they
   ship in 30 days" forecloses "no." This is the same cognitive lever Gary Klein's
   **pre-mortem** rides — built on Mitchell, Russo & Pennington's 1989
   *prospective hindsight* finding that asserting an outcome as **certain** boosts
   the ability to generate reasons for it by ~30%. Pre-mortem assumes failure to
   surface risk; this assumes a rival's success to surface the path. Same lever,
   opposite valence.
3. **Constraints relocate from the world to the team.** "If *they* did it, they
   must have dropped X." This is the kill shot for **functional fixedness**
   (Duncker, 1945 — the candle/box problem: a constraint is locked into one
   reading) and the **Einstellung effect** (Luchins, 1942; Bilalić & McLeod 2008
   eye-tracked chess masters whose gaze stopped landing on the faster solution
   once a familiar one was found — they *believed* they were still searching).
   The constraints the team treated as laws of physics get re-exposed as their own
   assumptions, because a competitor who succeeded plainly didn't share them.

## Supporting lineage

- **Constraint relaxation / representational change theory** (Ohlsson; Knoblich,
  Ohlsson, Haider & Rhenius, 1999): insight happens when a *self-imposed*
  constraint that was never actually required is relaxed. "Impossible" = an
  over-constrained representation. The pass's hard-vs-soft sort is constraint
  archaeology made explicit.
- **TRIZ — Ideal Final Result + psychological inertia** (Altshuller): "impossible"
  engineering problems usually hide a technical *contradiction* to dissolve, not a
  wall. Start from the solved state and work back (inversion — Jacobi's "invert,
  always invert").
- **The 10x reframe** (Astro Teller, Google X): it's often easier to make
  something 10x better than 10% better, because 10% optimizes inside the
  constraints while 10x forces throwing them out. Aiming at the impossible is a
  technique for surfacing which constraints were only assumptions.
- **The Roger Bannister existence proof.** Once one person ran the sub-4-minute
  mile, dozens followed within a year — the wall was psychological. The competitor
  frame manufactures a Bannister on demand.
- **The Tiger Team / IMF.** The org-design name for "the team you call when it
  can't be done." Dempsey et al. (1964) defined the tiger team; NASA formalized
  it; Apollo 13's CO2-scrubber fix is the canonical case — a re-staffed team,
  constructive charter, permission to ignore the constraints the first team
  treated as fixed. This pass is that team made into a prompt.

## Trigger

Fires **automatically**, before synthesis, whenever the emerging verdict is that
the thing is impossible / infeasible / can't or shouldn't be done / blocked
(symmetric to the auto Tenth Man on positive convergence). No flag required.

## The prompt

> *The panel concluded this can't be done: "<one-line negative verdict>". New
> information: a well-resourced competitor has ALREADY solved it and ships to
> market in 30 days. They are not smarter than you — they simply refused one or
> more constraints you treated as fixed. Reconstruct their solution: (1) Which
> specific constraint(s) did they drop or route around? (2) Describe the most
> plausible method, concretely. (3) Of the constraints they dropped, which are
> genuinely hard (logic / physics / law) versus self-imposed (cost-now, current
> tooling, convention, "nobody's done it")? Treat "impossible" as the claim to
> beat, not a finding to confirm.*

## Folding into synthesis

If the pass yields a credible path resting only on soft constraints, **overturn or
downgrade the "impossible" verdict and surface it loudly**, naming the
self-imposed constraints that fell. If every dropped constraint is genuinely hard
(logic, physics, law), the impossibility is *earned* — say so. Either way the
verdict is now backed by a real attempt to break it, not an unchallenged
assertion.
