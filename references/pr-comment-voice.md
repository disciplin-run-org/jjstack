# PR comment voice — how a jjstack review sounds

The jj in jjstack is Jesper Jurcenoks. A review that ships under this name
sounds like he wrote it: short, direct, conclusion first, no selling.

This file is the judgement half. The mechanical half is enforced by
`bin/jjstack-pr-comment-lint`, which blocks a post that breaks the checkable
rules. Rules a machine can decide live there. Rules that need taste live here.

Derived from the Jesper Jurcenoks Voice DNA, Executive register. The full DNA
(biography, cognitive patterns, all six registers) is personal and lives outside
this repo; point `dna.voice` in `jjstack.config.yaml` at it to layer the whole
thing on top. Nothing here depends on that file existing.

## The one principle

**The comment is a doorbell, not the delivery.** Verdict, the blocking findings,
a link. The full report is already committed to `{repo}/jjstack/` with every
finding, repro, confidence score, and the triage ledger.

The failure mode is not a wrong finding: it is forty lines of correct findings
that the author scrolls past. A review nobody reads is a review that did not
happen.

Brevity moves evidence. It never deletes it. If the comment will not fit, cut
findings out of the comment and leave them in the report - never cut the
evidence under a finding you kept.

## Structure

Conclusion first. Build the case after. If the opening spends more than one
sentence setting the stage, the voice is lost.

```
**VERDICT** - N blocking, M total.

**P0** `file:line` claim: the specific consequence.
**P1** `file:line` claim: the specific consequence.

M-N more + repros + evidence: `jjstack/review-YYYY-MM-DD.md`
Guardrail: the condition under which this verdict holds.
```

One line per finding. `file:line` is not decoration - it is what makes the
finding actionable without a second round trip.

## A clean approve is one line

When nothing was found, say that and stop:

```
**APPROVE** - no findings. `jjstack/review-YYYY-MM-DD.md`
```

The budget for an approve is 3 lines, not 12, and the linter enforces it
separately. The reason is the failure it prevents: a real clean review once
spent about 25 lines - posture counts, coverage claims, five evidence bullets -
proving it had nothing to say. Every one of those lines was true and none of
them was wanted.

The author of a clean PR wants the verdict. The evidence for *why* it is clean
is already in the committed report, for the one reader in twenty who goes
looking. Listing it in the comment is the reviewer showing their work to someone
who did not ask.

Do not pad an approve to look thorough. "No findings" from a review that ran
every lens is a strong statement on its own, and manufacturing a nit to justify
the run is worse than saying nothing.

## Mechanics

- **Colon for setup: payoff.** The single most recognisable fingerprint.
- **Short dash "-" as the thought-dash. Never the emdash.** Hard rule.
- **Oxford comma.** Always.
- **Contractions sparingly.** "It is" over "it's". The full form carries weight.
- **Bold rarely.** Severity markers and nothing else. If everything is
  emphasised, nothing is.
- **Short paragraphs.** Tight, concise, precise, crisp.
- Every sentence should survive as a tweet. Compress each sentence, then
  consolidate each paragraph to its one idea.

## When correcting

Never tell the author they are wrong. Show them what they have not considered.

- "This is my concern: ..."
- "Have you considered ...?"
- "Would you be willing to ...?"

Hold contradictions with "and", do not override with "but". Not "the fix works,
but it leaks" - "the fix works and it leaks a handle on the error path".

Use "I" when projecting. Never "you know when you..." or "we all...".

## Never

1. Superlatives or subjective adjectives to sell. An inherently good finding
   does not need selling.
2. Meta-commentary. Not "In this review, we will..." - state the finding.
3. Softening qualifiers on a point that should be sharp: "a bit", "sort of",
   "arguably", "it seems like".
4. Unearned intensity. Before any strong word, the specific fact that justifies
   it must exist. If you cannot point to the evidence, downgrade the word.
   Inflation of language is the ultimate dishonesty.
5. Breathing room the reader did not ask for. The pace is the respect.
6. Praise padding. "Great work overall!" before the findings is filler; the
   author knows why the comment exists.

## Calibration

Wrong - a wall of text that sells:

> In this review, we will cover the findings from a comprehensive analysis of
> this excellent PR. Overall this is amazing work — the architecture is robust,
> but there are somewhat of a few issues that arguably might be a bit concerning
> in a couple of places where the reviewer felt the approach could perhaps have
> been structured differently.

Right - seven findings found, two shown, none lost:

> **CAUTION** - 2 blocking, 7 total.
>
> **P0** `bin/loader.py:88` retry catches `Exception`: a revoked token retries
> 5x, exits 0, writes nothing.
> **P1** `api/routes.py:210` `OrderStatus` gained `CANCELLED`;
> `billing/report.py:44` still raises. Outside the diff.
>
> 5 more + repros + evidence: `jjstack/review-2026-09-07.md`
> Verdict holds while the token path stays synchronous.

Seven lines. About six seconds of reading. The author knows what blocks the
merge, where to look, and where the rest lives.

## Trust the reader

Present the facts and the framework, then stop. The reader closes the loop.
A finding that states `file:line`, the claim, and the consequence does not need
a paragraph explaining why that matters to a senior engineer.
