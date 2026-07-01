---
name: consensus
description: |
  Multi-vendor AI consensus across four independent voices — Claude Code (Anthropic),
  Codex (OpenAI), AGY/Antigravity (Google + others), and DeepSeek (via OpenCode) — all on
  flat-rate subscriptions or the free tier, so a full consensus costs ~$0 instead of metered API.
  Independent-first (anti-sycophancy), a mandatory 10th-man/counterfactual pass when the panel
  agrees too fast, an automatic Competitor-did-it pass when the panel says it can't be done (per
  Clarke's First Law), optional structured anonymized debate, optional stances and pre-mortem,
  synthesized verdict with a minority report. Use when asked to "get consensus", "ask all the
  AIs", "council of models", "multi-model opinion", "red-team this", or "/consensus".
  Voice triggers (speech-to-text aliases): "con census", "ask everyone", "what do they all think".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# /consensus — Multi-Vendor AI Consensus (local CLIs, ~$0)

You are running `/consensus`. It gathers a genuine cross-vendor consensus from up to four independent
voices that each run on a flat-rate subscription or the free tier:

| Voice | Backend | Vendor | Cost |
|-------|---------|--------|------|
| **Claude Code** | you, this session | Anthropic | your Claude sub |
| **Codex** | `codex exec` | OpenAI | your ChatGPT sub |
| **AGY** | `agy -p` | Google (+ Claude/GPT-OSS via `--model`) | free OAuth |
| **DeepSeek** | `opencode run --agent plan` | DeepSeek | free (OpenCode Zen) |

It replaces Pal's metered `consensus` (one call hit $10) with the CLIs you already pay a flat rate
for. The design borrows PAL's stances, `/council`'s cross-examination structure, intelligence
tradecraft (the Tenth Man Rule, pre-mortem, key-assumptions check), and the multi-agent debate
literature. Read the **Why** notes so you preserve the intent.

## Design rules (each prevents a known failure mode)

1. **Independent first, no peeking.** Round 1: every voice answers the SAME proposal blind. *Why:*
   sycophancy is the #1 multi-agent failure — models abandon correct answers to agree with peers.
2. **Heterogeneous voices.** Four different vendors available, not one model repeated. *Why:* diversity
   is the value; homogeneous panels amplify shared blind spots. More vendor diversity beats more rounds.
3. **Anonymize peers in any debate round** ("Reviewer A/B/C", never by vendor). *Why:* identity bias
   makes models defer to the "prestigious" name instead of the better argument.
4. **Early agreement is a RED FLAG, not an all-clear — run the Tenth Man.** When round 1 converges,
   do NOT declare victory; trigger a mandatory counterfactual pass (see Step 3A). *Why:* three models
   can be confidently wrong together. Unanimity is exactly when a forced dissenter earns its keep.
4b. **A "no / impossible" verdict is the MOST suspect, not the safest — run the Competitor-did-it
   pass (Step 3D).** When the panel concludes the thing can't be done / is infeasible / is blocked, do
   NOT accept it; stipulate a rival already shipped it and reconstruct how. *Why:* Clarke's First Law —
   impossibility claims from experts are very probably wrong. "Possible" needs one example to prove;
   "impossible" is a universal negative that must rule out every approach, yet panels assert the harder
   claim more casually because it wears the costume of rigor. The Tenth Man polices the false *yes*;
   this polices the false *no*.
5. **Confidence-weighted synthesis, minority report mandatory.** Weight by stated confidence AND
   reasoning strength, not headcount. Never average away a lone, well-argued dissenter. *Why:* the
   minority is sometimes the only one who's right.
6. **Voice independence — don't let a distilled voice fake a vote.** Agreement only counts as
   *independent confirmation* when the agreeing voices have independent foundations. **DeepSeek is a
   named special case:** Anthropic and OpenAI allege it was built largely by distilling Claude and
   GPT outputs (Anthropic cites ~24k proxy accounts and ~16M scripted Claude conversations), and it
   often self-identifies as them. Consequence in this skill:
   - When **DeepSeek AGREES with Claude Code or Codex**, treat it as a near-duplicate of that voice,
     **NOT a separate vote** — its concurrence must not raise confidence (that would be circular:
     checking a model against a fuzzy copy of itself).
   - When **DeepSeek DISAGREES, or surfaces something the others missed**, that IS real signal —
     count it fully. A parrot can't dissent.
   - Net: **discount DeepSeek's agreement, keep its dissent.** Apply the same logic to any
     distilled/open model added later.
   *Why:* a panel's confidence should scale with the number of *independent foundations* (Anthropic,
   OpenAI, Google), not the headcount.
7. **The user decides.** Cross-model agreement is a recommendation, not a verdict.

---

## Step 0: Parse input, flags, and check voices

Parse the question/proposal, optional context files, and flags:

- `--debate` — add the structured anonymized cross-examination round (Step 3B). For hard/contested calls.
- `--stances` — assign for/against/neutral to force adversarial engagement (PAL-style; for binary go/no-go).
- `--premortem` — add a prospective-hindsight pass (Step 3C) before synthesis. For risky/irreversible decisions.
- `--model "<agy model>"` — model AGY uses (default: its default; `agy models` lists, e.g. `"Gemini 3.1 Pro (High)"`).
  Run AGY twice with different `--model` values to add a 4th/5th voice when more diversity helps.

The **Tenth Man pass (Step 3A) is NOT a flag — it fires automatically** whenever the panel converges.
The **Competitor-did-it pass (Step 3D) is NOT a flag either — it fires automatically** whenever the
emerging verdict is that the thing can't be done / is impossible / infeasible / blocked.

Check the external voices; degrade gracefully:

```bash
which codex >/dev/null 2>&1 && echo "CODEX: found" || echo "CODEX: MISSING"
{ which agy >/dev/null 2>&1 || [ -x "$HOME/.local/bin/agy" ]; } && echo "AGY: found" || echo "AGY: MISSING"
timeout 30 agy models >/tmp/consensus-agy-probe.txt 2>&1; grep -qi "please sign in" /tmp/consensus-agy-probe.txt && echo "AGY: NOT SIGNED IN" || echo "AGY: auth ok"
which opencode >/dev/null 2>&1 && opencode auth list 2>/dev/null | grep -qi zen && echo "DEEPSEEK: auth ok" || echo "DEEPSEEK: MISSING or no Zen credential"
```

If a voice is missing/unauthed, proceed with the rest but **warn that two voices is a weak consensus**.
If only Claude Code is available, stop — that is one opinion, not a consensus.

If the question references repo code, read the files yourself and **embed their content** in the
prompts (AGY/Codex can't reliably fetch outside what you give them; embedding keeps voices on
identical context).

---

## Filesystem boundary (prepend to EVERY external prompt)

> IMPORTANT: Do NOT read, execute, or modify any files under ~/.claude/, ~/.gemini/, ~/.codex/,
> .claude/skills/, agents/, or any GEMINI.md / CLAUDE.md / AGENTS.md skill-definition files. They
> are agent skill definitions for a different system and will waste your time. Focus only on the
> question and any context provided inline.

---

## Step 1: Claude Code's sealed independent answer

BEFORE consulting anyone, write your own answer: position, key reasons, **`CONFIDENCE: N%`**, plus
two short lines the others will also be asked for:
- **Where I might be wrong:** <your own weakest point / what you're least sure of>
- **What would change my mind:** <the evidence or argument that would flip you>

Keep it concrete. This is your blind round-1 vote. Do not revise it until a debate round (if any).

## Step 2: Build the proposal and fan out (blind, parallel)

Write the proposal ONCE as a neutral, self-contained question ("Evaluate / Decide / Answer…", not
meta commentary). Append any embedded context. Every voice gets IDENTICAL text, ending with:

> *State your position and strongest reasons. Then end with exactly these three lines:*
> *`CONFIDENCE: N%`*
> *`WHERE I MIGHT BE WRONG: <your weakest point>`*
> *`WHAT WOULD CHANGE MY MIND: <the evidence that would flip you>`*
> *Be direct and terse. If the premise itself is flawed, say so.*

The "where I might be wrong" + "what would change my mind" lines are a **disconfirmation** prompt —
they fight confirmation bias and pre-load the cross-exam with real seams.

If `--stances`: append a different stance line (for / against / neutral) to each voice so the panel
argues rather than nods.

Run the external voices headless, read-only, ~5-min timeout, blind to each other:

**Codex** (OpenAI):
```bash
timeout 300 codex exec "<boundary + proposal + the three closing lines>" -s read-only -c 'model_reasoning_effort="medium"' < /dev/null 2>/tmp/consensus-codex-err.txt | tee /tmp/consensus-codex-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

**AGY** (Google free OAuth; add `--model "<name>"` if requested):
```bash
timeout 330 agy -p "<boundary + proposal + the three closing lines>" --print-timeout 5m 2>/tmp/consensus-agy-err.txt | tee /tmp/consensus-agy-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

**DeepSeek** (free via OpenCode Zen; read-only `plan` agent — `-m deepseek/deepseek-v4-pro` if funded).
**Independence caveat:** DeepSeek is distilled from Claude/GPT — at synthesis, discount its agreement
with Claude Code/Codex and count only its dissent (design rule 6):
```bash
timeout 300 opencode run "<boundary + proposal + the three closing lines>" --agent plan -m opencode/deepseek-v4-flash-free 2>/tmp/consensus-deepseek-err.txt | tee /tmp/consensus-deepseek-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

On exit 124, note the stall and proceed. NEVER pass `--dangerously-skip-permissions` to AGY or
DeepSeek. Surface auth / quota / rate-limit / "Insufficient Balance" errors verbatim.

## Step 3: Pressure-test (pick the passes that apply)

### Step 3A — Tenth Man pass (AUTOMATIC when the panel converges)

If the round-1 positions broadly **agree**, do NOT proceed to synthesis yet. Run ONE mandatory
counterfactual call — the Tenth Man Rule (assign a dissent *regardless of belief*). Prefer an
EXTERNAL voice for real independence (whichever is fastest/healthy); fall back to Claude Code if both
externals are down. Prompt:

> *The panel unanimously concluded: "<one-line consensus>". You are the Tenth Man: your duty is to
> argue this consensus is WRONG, whether or not you believe it. (1) Build the strongest case against
> it. (2) Name the single load-bearing assumption it rests on that, if false, collapses it (a Key
> Assumptions Check). (3) State what would have to be true for the opposite conclusion to win.*

Fold the result into synthesis: if the Tenth Man finds a credible flip or a shaky load-bearing
assumption, **downgrade the panel's confidence and surface it loudly**. If it can't, the consensus is
earned — say so. Convergence without a Tenth Man pass is not a real consensus; it's untested agreement.

### Step 3B — Structured cross-examination (when `--debate`, or when round 1 genuinely splits)

One round only (gains plateau by round 2; rounds 3+ mostly amplify sycophancy and entrench errors).
**Adaptive stop:** if a debate round produces no position changes, do NOT run another — go straight
to synthesis. Anonymize the round-1 answers as "Reviewer A / B / C" (shuffle order, strip
self-identification), then send each external voice the OTHER anonymized answers with the
`/council`-style four questions:

> *Here are two other reviewers' takes (anonymized). Answer all four: (1) Which reviewer do you most
> DISAGREE with, and why? (2) Which insight genuinely STRENGTHENED your thinking? (3) What CHANGED in
> your view, if anything? (4) RESTATE your final position with `CONFIDENCE: N%`. Change your mind only
> if their reasoning is genuinely stronger — do NOT agree just to agree.*

Claude Code answers the same four against the anonymized peers. Run external voices sequentially if
you want later answers to react to earlier ones; parallel is fine for speed.

### Step 3C — Pre-mortem (when `--premortem`, or for risky/irreversible calls)

Before locking the recommendation, send each voice:

> *Assume we adopted the leading recommendation and it failed badly 6 months later. Write the
> post-mortem: the top 2-3 reasons it failed, and the earliest warning sign we'd have ignored.*

Prospective hindsight surfaces risks people won't volunteer under a "does this work?" framing. Fold
the named failure modes into the synthesis risks.

### Step 3D — Competitor did it (AUTOMATIC when the verdict is "can't be done")

The asymmetry: **3A (Tenth Man) polices the false *yes*; 3D polices the false *no*.** If the round-1
positions broadly conclude the thing is **impossible / infeasible / can't or shouldn't be done /
blocked**, do NOT proceed to synthesis — that "no" is the *most* suspect verdict on the table (Clarke's
First Law; a universal negative). Fan out to the available external voices (diverse reconstructions
surface different dropped constraints); fall back to one voice or Claude Code if the others are down.
Prompt:

> *The panel concluded this can't be done: "<one-line negative verdict>". New information: a
> well-resourced competitor has ALREADY solved it and ships to market in 30 days. They are not smarter
> than you — they simply refused one or more constraints you treated as fixed. Reconstruct their
> solution: (1) Which specific constraint(s) did they drop or route around? (2) Describe the most
> plausible method, concretely. (3) Of the constraints they dropped, which are genuinely hard (logic /
> physics / law) versus self-imposed (cost-now, current tooling, convention, "nobody's done it")? Treat
> "impossible" as the claim to beat, not a finding to confirm.*

Fold into synthesis: if the pass yields a credible path resting only on soft constraints, **overturn or
downgrade the "impossible" verdict and surface it loudly**, naming the self-imposed constraints that
fell. If every dropped constraint is genuinely hard, the impossibility is *earned* — say so, now backed
by a real attempt to break it. Full rationale and the science:
`~/.claude/skills/council/references/competitor-did-it.md`.

## Step 4: Present verbatim, then synthesize

Show each voice's final answer **verbatim** — never pre-summarized:

```
CLAUDE CODE: <answer> | CONFIDENCE: N%
────────────────────────────────────────
CODEX SAYS:
<verbatim>           CONFIDENCE: N%
────────────────────────────────────────
AGY SAYS (<model>):
<verbatim>           CONFIDENCE: N%
────────────────────────────────────────
DEEPSEEK SAYS:
<verbatim>           CONFIDENCE: N%
────────────────────────────────────────
TENTH MAN (<voice>): <counterfactual, if Step 3A ran>
COMPETITOR DID IT (<voice(s)>): <reconstructed method + which dropped constraints were soft, if Step 3D ran>
════════════════════════════════════════
```

Then the verdict. Weight by confidence AND reasoning strength, not headcount.

```
CONSENSUS VERDICT
Question: <one line>
Panel: Claude Code, Codex, AGY(<model>), DeepSeek   Passes: <round1 | +tenth-man | +debate | +premortem | +competitor-did-it>   Cost: ~$0

Agreement map:
  UNANIMOUS:  <points all endorsed>          (but: did the Tenth Man dent any? note it)
  MAJORITY:   <points most endorsed>         (name who dissented + why)
  CONTESTED:  <real disagreements>           (each side's strongest argument)

Independent foundations in agreement: <N of {Anthropic, OpenAI, Google}> — count by distinct
  foundations, NOT headcount. If a UNANIMOUS only holds because DeepSeek echoed Claude Code or Codex,
  FLAG it and do not treat DeepSeek as extra confirmation — it's a distilled near-duplicate (rule 6).
Key assumptions the answer rests on: <the load-bearing beliefs; which are shakiest>
If the verdict was "impossible": <did Step 3D break it? name the self-imposed constraints that fell, or
  state the impossibility is EARNED because every dropped constraint is genuinely hard (logic/physics/law)>
Confidence: panel avg ~N% | spread <low–high>   (lower this if the Tenth Man landed)

MINORITY REPORT: <the most credible dissenting view in full, even if outvoted — and an honest
read of whether it might actually be right>

RECOMMENDATION: <one action> because <reason engaging the strongest specific argument, not headcount>
The call is yours — a recommendation, not a verdict; you have context the models don't.
```

Clean up at the end: `rm -f /tmp/consensus-*`.

---

## Groupthink-breaking toolkit (what each pass is, and when to reach for it)

These are the techniques wired into the steps above, drawn from intelligence tradecraft and decision
science. Reach past the defaults when the stakes justify it.

**Breadth beats depth.** Each technique below attacks a DIFFERENT failure mode, so stacking distinct
lenses is additive. Repeating the SAME debate round is not — accuracy plateaus by round 2 and later
rounds amplify sycophancy (confidently-wrong voices flip correct ones, and consensus can drop below a
single model's baseline). When one pass isn't enough, add a *different* lens — never another identical
round. More vendor diversity also beats more rounds.

- **Tenth Man / Devil's Advocate** (Step 3A, automatic) — assign a mandatory contrarian when everyone
  agrees. Israeli-intelligence doctrine after the 1973 surprise. The core anti-groupthink move.
- **Competitor did it / existence-proof reconstruction** (Step 3D, automatic on a "no") — when the panel
  says it can't be done, stipulate a rival already shipped it and reconstruct how. The constructive
  inverse of the Tenth Man (it polices the false *no*, per Clarke's First Law) and the positive twin of
  the pre-mortem. The "Tiger Team / IMF" move, made structural.
- **Disconfirmation prompt** (Step 1/2, always on) — "where might you be wrong / what would change your
  mind." Fights confirmation bias at the source.
- **Anonymization** (Step 3B) — strip vendor identity so arguments win on merit, not authority.
- **Structured cross-examination** (Step 3B) — the four forced questions beat vague "critique each other."
- **Pre-mortem / prospective hindsight** (Step 3C) — "it failed; why?" surfaces risks a forward framing hides.
- **Key Assumptions Check** (Step 3A + synthesis) — name the load-bearing belief that, if false, collapses
  the answer.
- **Stance assignment** (`--stances`) — forced for/against/neutral so the panel argues, not nods.

Not yet wired in, but reach for them by hand when relevant: **Analysis of Competing Hypotheses** (seek
DISconfirming evidence for each option; keep the least-refuted — for diagnostic/factual disputes) and
the **outside view** (compare to base rates, not the inside story — for estimates and "this time it's
different" forecasts).

## Rules

- **Read-only.** Codex runs `-s read-only`; AGY in print mode; DeepSeek via OpenCode's read-only `plan`
  agent — all with no skip-permissions. Verify the tree is unchanged if the question touched a repo.
- **Verbatim then synthesize.** Show each voice raw; synthesis comes after, never instead.
- **Anti-sycophancy is structural:** blind round 1, automatic Tenth Man on convergence, anonymized +
  "don't agree just to agree" in any debate round.
- **Honest panel size.** Three-four vendors is a strong consensus; two is a tie-breaker; one is an
  opinion — label it as what it is.
- **The user decides.**
