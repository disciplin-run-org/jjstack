---
name: council
version: 1.2.0
description: Run a structured multi-perspective council on a hard decision, design choice, debugging question, strategy problem, or tradeoff. Use when the user wants multiple viewpoints, explicit cross-examination, and a compact final verdict.
---

# Council

Use this skill when the user wants a multi-perspective council rather than a
single answer. Good triggers include:

- "run a council on this"
- "get multiple perspectives"
- "debate this decision"
- "stress test this plan"
- architecture, product, strategy, debugging, risk, or founder tradeoffs

If `$ARGUMENTS` is non-empty, treat it as the problem statement. Otherwise ask
the user for the question to deliberate on.

## Defaults

- Prefer 3 members unless the user asks for a full panel or the problem is
  unusually ambiguous.
- Default to a CEO/architect/skeptic triad if nothing else is specified.
- Keep the final verdict compact unless the user asks to see the rounds.

## Workflow

### 1. Resolve The Panel

Honor, in order:
1. explicit `--members` flag
2. explicit `--triad` flag
3. explicit `--profile` flag
4. keyword triad match from the problem statement
5. fallback default (CEO + architect + skeptic)

### 2. Round 1: Independent Analysis

- Run each selected member independently.
- Keep round 1 blind-first: each member sees only the problem statement and
  their own persona text.
- Ask for a compact standalone analysis ending with a clear verdict,
  confidence, and where the member may be wrong.

Preferred orchestration: use parallel or forked agent contexts when available.
If not easy to access, keep the protocol in the main session and separate
member outputs clearly.

Suggested round 1 packet:

```text
You are operating as one member of a structured council.

Persona: {persona}
Problem: {problem}

Produce a compact standalone analysis.
End with a clear verdict, confidence, where you may be wrong, and what would change your mind.
Do not anticipate the other members.
```

### 3. Round 2: Cross-Examination

- Share round 1 outputs with each member.
- Ask each member to:
  - name the position they most disagree with and why
  - name one insight that strengthened their thinking
  - say whether anything changed
  - restate their position after the exchange
- Prefer sequential execution so later responses can react to earlier disagreements.

```text
Here are the other council members' round 1 analyses:

{peer_outputs}

Respond to all of the following:
1. Which member do you most disagree with, and why?
2. Which member strengthened your thinking, and how?
3. What changed, if anything?
4. Restate your position after the exchange.

Keep it compact and engage at least two members by name.
```

### 4. Round 3: Final Position

- Short final stance only.
- No new arguments.

### 5. Synthesis

- Default to final verdict only.
- If user asks to see rounds, include concise round summaries after the verdict.

## Fallback Mode

If multi-round orchestration is impractical:
1. Simulate round 1 as clearly separated persona sections
2. Simulate round 2 as explicit cross-exam sections
3. Simulate round 3 as final positions
4. Disclose that you used the single-agent fallback

## Guardrails

- Do not force consensus.
- If the panel converges too quickly, run one counterfactual pass (the Tenth Man) plus a Key Assumptions Check.
- Adaptive stop: if Round 2 produced no position changes, skip Round 3 and synthesize.
- For risky or irreversible decisions, run a pre-mortem before synthesis.
- If the panel concludes the thing **can't be done**, run the Competitor-did-it pass: stipulate a well-resourced rival has ALREADY shipped it in 30 days, and have each member reconstruct the method. Sort dropped constraints into genuinely hard (logic/physics/law) vs. self-imposed (cost-now, tooling, convention). If a credible path falls out, overturn or downgrade the "impossible" verdict loudly.
- Keep personas attributed — the identity IS the signal (do NOT anonymize).
- Prefer substance over theater: the council should improve the answer, not just decorate it.
