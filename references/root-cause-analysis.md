# Root-Cause Analysis — Verified Contributing-Factors Tree

The method `/investigate` runs after gstack's own root-cause pass. It
replaces "5 Whys" (which fails inconsistently for laypeople) with a
structured, evidence-gated tree that gives reproducible results
regardless of who's driving the session.

## Why 5 Whys fails in practice

1. **Assumes a single chain.** Real failures are conjunctions — the
   bug happened because A *and* B *and* C. A linear why-ladder picks
   one limb arbitrarily and misses the others.
2. **No evidence gate.** "Because the deploy was rushed" sounds like a
   cause but isn't verifiable. Novices accept plausibility; experts
   demand a log line, a diff, a reproducible command.
3. **Stops at the asker's mental model.** Whoever runs the session
   can't dig past what they already understand.
4. **Ambiguous stop criterion.** "Keep asking until you reach the
   root" — what IS the root? Depth 5 is an arbitrary number.
5. **Person-blame attractor.** Without discipline the chain
   terminates at "someone should have caught it," which is not
   actionable.

## The method

Borrows from Apollo RCA (two-cause model), blameless post-mortems
(contributing factors plural), and Kepner-Tregoe Problem Analysis
(is/is-not scoping). Four rules, executed in order.

### Rule 1 — Scope before explain

Before any "why," write down the problem's shape:

```
PROBLEM SCOPE
  IS:       <what, where, when, how much>
  IS NOT:   <what it could be but isn't, where it doesn't occur,
             when it's absent>
  STARTED:  <first observation, last known good>
```

Is/Is-Not is from Kepner-Tregoe. It kills bad hypotheses immediately —
"it's a DNS issue" dies the moment you note "IS NOT: fails the same
way on the IP directly."

Minimum fields: what / where / when / extent / boundary.

### Rule 2 — Every effect has at least two causes

Not "why" singular — "what ACTION occurred AND what CONDITION let it
propagate." From Apollo RCA.

- **Action** — the thing that happened (a request fired, a value was
  written, a process started).
- **Condition** — the state that made the action harmful (a null
  wasn't checked, a lock wasn't held, an index wasn't built).

A null pointer isn't root-caused by "x was null." It's:

- ACTION: caller passed x=null
- CONDITION: callee didn't check

Both must be present, both must be documented. This forces breadth
before depth.

### Rule 3 — Every claim carries evidence and confidence

Each node in the tree has three fields:

```
claim:      <the causal statement>
evidence:   <inspectable artifact: log line, git-blame line,
             failing test, reproducible command, diff>
confidence: verified | hypothesis
```

- **verified** — evidence has been inspected and supports the claim.
- **hypothesis** — plausible but not yet confirmed. The tree can
  branch into hypotheses for parallel exploration, but a hypothesis
  cannot be the terminal stop.

This is the gate that separates expert from layperson. Laypeople
accept plausibility. The rule forces verification.

### Rule 4 — Stop at the class boundary, not a depth counter

The stop condition is: **can I write the regression test that would
catch this class of failure?**

Not "did I hit 5 whys." Depth is irrelevant; sufficiency is what
matters. If you can write the test, you've found the actionable root.
If you can't, keep going — whatever you have is still proximate.

"Class" is important. "A test that catches this exact null pointer"
is too narrow. "A test that catches any caller passing null to this
interface" is right — it covers the class.

## Tree shape

Output a tree, not a chain. Minimum structure:

```
PROBLEM SCOPE
  IS:       ...
  IS NOT:   ...
  STARTED:  ...

FAILURE
├── ACTION: <what happened>
│     claim:      ...
│     evidence:   ...
│     confidence: verified
│     └── PRIOR ACTION (if applicable): ...
│
└── CONDITION: <what allowed it>
      claim:      ...
      evidence:   ...
      confidence: verified
      └── PRIOR CONDITION (if applicable): ...

AND-BRANCHES (if multi-cause conjunction):
  - <claim + evidence>

STOP CHECK
  regression test:
    <literal code or pseudo-code that would fail before the fix,
     pass after, AND fail for the whole class of this failure>
  class boundary:
    <one-sentence description of the failure class this test covers>
```

Every leaf is either `verified` or an acknowledged hypothesis carried
into the STOP CHECK as "test would detect this IF hypothesis true."

## Anti-patterns this method kills

- **Chain that terminates at "human error"** — Rule 2 forces a
  condition node (what system state allowed the person to make the
  error). "Engineer rushed" is an action; the condition is "no gate
  existed to slow them down."
- **Stopping at the first plausible cause** — Rule 3's confidence
  field makes hypothetical stops visible. Rule 4 disallows them as
  terminal.
- **Narrow regression tests** — Rule 4's "class boundary" requirement
  catches tests that would fix this one bug but not the pattern.
- **Skipping scope** — Rule 1 is cheap and usually the step people
  skip. Without it, every other step drifts into overreach.

## Example (abbreviated)

**PROBLEM SCOPE**
- IS: Settings page flashes "configured" but API keys aren't persisted. Observed on 3 user reports over 2 days.
- IS NOT: Does not affect non-API-key settings (theme, model). Does not happen in cypress tests.
- STARTED: Earliest report 2026-04-14; no known-good date before that.

**FAILURE: API keys lost silently after save**

ACTION:
- claim: autoSave() was called with a valid key payload
- evidence: `git log -S autoSave src/Settings.tsx` → commit 3f4e2ba introduced the call
- confidence: verified

CONDITION:
- claim: `autoSave(...).catch(() => {})` swallowed the "Missing session ID" error
- evidence: grep shows the empty catch in src/api.ts:82; server logs show "Missing session ID" responses at matching timestamps
- confidence: verified
- PRIOR CONDITION: no lint rule blocks empty catch arms
  - evidence: `.eslintrc.json` has no `no-empty-catch` equivalent
  - confidence: verified

STOP CHECK:
- regression test:
  ```ts
  it("does not flash 'configured' on save failure", async () => {
    server.use(errorResponse(401, "Missing session ID"));
    await user.click(saveButton);
    expect(screen.queryByText(/configured/i)).toBeNull();
    expect(screen.getByRole("alert")).toHaveTextContent(/session/i);
  });
  ```
- class boundary: covers all save paths where optimistic UI could diverge from actual server state.

## When to use this

- `/investigate` runs it after gstack's own RCA pass (see the
  wrapper's Phase 4 for automated enforcement).
- Any incident post-mortem.
- Any bug report that matters enough to write a regression test for.

## When NOT to use this

- Trivial typo fixes. Overhead isn't justified.
- Obvious single-cause bugs where the fix is already landed and
  verified. Still worth writing the regression test, but the tree
  is skippable.
- Exploration / refactoring where there's no "failure" to trace
  back from.
