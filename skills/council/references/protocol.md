# Council Protocol

This protocol is harness-agnostic. Adapters should map it onto the local orchestration features of the host environment.

## Inputs

- problem statement
- optional profile
- optional triad
- optional explicit member list
- optional `show_rounds` flag

## Panel Selection

1. If the user specifies `--members`, use exactly those members.
2. Else if the user specifies `--triad`, resolve that triad inside the chosen profile.
3. Else if the user specifies `--profile`, use that profile's default triad.
4. Else inspect the problem statement for a known keyword triad.
5. Else use `classic` + `architecture`.

Default behavior should prefer 3 members for speed and clarity. Use the full panel only when the user asks for it or when the decision is unusually ambiguous.

## Round 1: Independent Analysis

- Run each selected member independently.
- Keep the first round blind-first: each member sees the problem statement and their own persona only.
- Ask for a compact standalone analysis with a clear verdict and confidence level.
- Require each member to end with two disconfirmation lines: **where they might be wrong**, and
  **what evidence would change their mind**. The second is a flip-trigger that pre-loads the cross-exam.
- Prefer parallel execution when the harness supports it.

## Round 2: Cross-Examination

- Share the round 1 outputs with each member.
- Ask each member to:
  - name the position they most disagree with and why
  - name one insight that strengthened their thinking
  - say whether anything changed
  - restate their position after the exchange
- Prefer sequential execution so later responses can react to earlier cross-exams.

## Round 3: Final Position

- Ask for a short final stance only.
- No new arguments unless a harness limitation forces a condensed fallback.
- Socrates may ask one final question before stating a position.

## Optional: Pre-mortem (risky or irreversible decisions)

Before synthesis, ask the panel to assume the leading recommendation was adopted and failed badly six
months later, and to write the post-mortem: the top 2-3 reasons it failed and the earliest warning
sign that would have been ignored. Prospective hindsight surfaces risks members will not volunteer
under a "does this work?" framing. Fold the named failure modes into the synthesis risks.

## Automatic: Competitor-did-it (impossibility verdicts)

The constructive twin of the pre-mortem and the inverse of the Tenth Man. If the panel concludes the
thing **can't be done / is impossible / infeasible / blocked**, do NOT accept that "no" — per Clarke's
First Law it is the most suspect verdict on the table (a universal negative: "possible" needs one
example, "impossible" must rule out every approach). Before synthesis, tell each member that a
well-resourced competitor has ALREADY solved it and ships to market in 30 days, and ask them to
reconstruct it: (1) which specific constraint(s) the competitor dropped or routed around, (2) the most
plausible method, concretely, and (3) of the dropped constraints, which are genuinely hard (logic /
physics / law) vs. self-imposed (cost-now, tooling, convention, "nobody's done it"). Stipulated
certainty flips the question from "can it?" (invites "no") to "they did — how?" (generative
reconstruction). If a credible path falls out resting only on soft constraints, overturn or downgrade
the "impossible" verdict and name the self-imposed constraints that fell; if every dropped constraint
is genuinely hard, the impossibility is earned. Full science: `competitor-did-it.md`.

## Synthesis

Use the verdict template and report:

- problem
- composition
- consensus or lack of consensus
- points of agreement
- points of disagreement
- key assumptions the conclusion rests on (and which are shakiest)
- minority report
- pre-mortem failure modes (if that pass ran)
- competitor-did-it path and the self-imposed constraints that fell (if that pass ran)
- unresolved questions
- recommended next steps

Keep the default output compact. Only include round transcripts when the user asks for them.

## Enforcement Rules

- Do not allow recursive questioning loops.
- Require real disagreement before declaring consensus.
- If consensus arrives too early, run one counterfactual pass (the Tenth Man):
  - Assume the current consensus is wrong. What strongest alternative would flip the decision?
  - Name the single load-bearing assumption the consensus rests on that, if false, collapses it
    (Key Assumptions Check).
- The asymmetry (Clarke's First Law): the Tenth Man polices a "yes". If instead the verdict is a "no"
  — the thing can't be done / is impossible — run the **Competitor-did-it** pass (see above) before
  synthesis. A "no" is a universal negative and the more suspect verdict; it does not get a free pass.
- Adaptive stop: if Round 2 produced no position changes, skip Round 3 and synthesize. Accuracy
  plateaus by round 2; extra rounds mostly amplify sycophancy and entrench errors.
- If the harness cannot support multi-round orchestration, simulate the same structure in one agent and disclose that fallback.

## Graceful Fallback

When a harness cannot spawn subagents or parallelize:

1. simulate round 1 as clearly separated persona sections
2. simulate round 2 as explicit disagreements between those sections
3. simulate round 3 as short final positions
4. synthesize the verdict in the same format
