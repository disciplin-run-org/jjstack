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

**Parsimony — respect the prior.** When a source of truth reports "X
passes / works" (a green test, a passing suite, a "the backend returns
this"), X is your prior. You may overturn it only by *reproducing X
failing* — never by inventing a *second* broken thing (a "false-green,"
a "silently unimplemented backend") to preserve a first assumption.
Prefer the explanation that invents the fewest new defects. A session
told "mcp:1.2.17 is green" that concludes the test is lying AND the
backend is broken has manufactured two bugs to avoid checking one.

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

**"Inspectable" is not enough — the probe itself must be sound.**
Evidence can be inspectable and still wrong. A grep that returns
nothing is inspectable; it is also worthless if the grep couldn't have
matched. Three sub-rules close that hole:

- **3a — Negative evidence is the weakest evidence.** A grep-miss, an
  empty result, a "not found" can mean the thing is absent OR your
  probe was malformed. Before a negative result becomes a claim, run a
  **positive control**: point the same probe at a value you *know* is
  present. If the control also comes back empty, your probe is broken —
  not the system. Worked failure: grepping `"product":` against a
  response whose JSON is backslash-escaped (`\"product\":`) returns zero
  hits; the field was there the whole time. A one-line positive control
  ("does this probe find `scope`, which I know is present?") would have
  exposed the broken probe before it became a three-cause RCA.

- **3b — Read structured data through its consumer's parser.** JSON and
  other wire payloads get parsed the way the real consumer reads them
  (`json.loads`, the SDK, the deserializer under test) — never grepped
  as raw text. Evidence gathered through a *different representation*
  than the code path under test is not evidence about that path.

- **No action before `verified`.** A root cause at `hypothesis`
  confidence may not trigger any downstream action: no work order filed,
  no fix applied, no spec edited, no worker dispatched. The tree must
  first reach a `verified` leaf backed by a *reproduced* failure. Acting
  on a hypothesis is how a broken grep becomes two real workers churning
  on fabricated tasks.

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
- **Trusting a negative probe** — Rule 3a. Treating "my search found
  nothing" as "the thing does not exist," with no positive control to
  prove the search could have found it.
- **Manufacturing a second bug** — Rule 1 parsimony. Explaining away a
  passing test by positing it is a false-green AND the feature is
  unimplemented, instead of reproducing the failure the green denies.
- **Acting on a hypothesis** — Rule 3's no-action gate. Filing a work
  order or dispatching a worker off a cause that is still unverified.

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

## Generated-artifact bugs — climb the generation chain

When the failing artifact is *generated* — a Python test compiled from
Gherkin compiled from a natural-language description — the defect can
live at any layer, and patching the leaf blesses the bug one level up.
Do not fix the generated test. Climb the chain, asking at each rung
whether the layer is faithful to the one above it:

1. **The test** — does it faithfully implement the Gherkin? A weak
   assertion (a bare substring `assert "product" in response`) can pass
   for the wrong reason: the key, any value, or the word "product" in
   unrelated prose all satisfy it. Faithful compile of a weak Gherkin is
   not the test's fault — climb.
2. **The Gherkin** — is it unambiguous? "The response contains product"
   never says key vs. value vs. word, so the generator picks the weakest
   reading. Ambiguity here is inherited from above — climb.
3. **The description** — is it sound, or does it conflate two layers?
   The canonical smell: **one behavior describing an outcome that spans
   two layers** — a backend contract ("a root read returns the product
   field") *and* a UI outcome ("the SPA labels the working area with
   it"). An MCP behavior can only test the backend half, so the
   generated test covers half; the broken half (the UI) has no behavior,
   no Gherkin, no test, and the green reads as "the feature works
   end-to-end" when it only means "the backend returns the field."

Fix at the layer where the defect *enters* (usually the description:
de-conflate it into one behavior per layer, and sharpen the surviving
Gherkin to assert the *value*, not mere presence). Then **regenerate
downward one step at a time** — new Gherkin from the clean description,
new test from the Gherkin — until a test goes **red on a real bug**. A
green that never went red proved nothing; the goal is a test that fails
before the fix and passes after. See the spec-cleanup playbook's Overstep
smell and Not-MCP-testable flagging for the layer-migration mechanics.

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
