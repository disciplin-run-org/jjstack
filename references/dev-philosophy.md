# Development Philosophy — 11 Layers

Getting more specific by layer. Each layer constrains the next. Never skip a
layer — if you're writing code (layer 11) without knowing the KPI it moves
(layer 6), you're building the wrong thing.

---

## Layer 1: Vision (century)

A purpose that unites the organization and outlasts any single product, market,
or technology cycle. Unchanged for a century.

Source: Jim Collins, *Built to Last* — the core ideology that defines why the
organization exists beyond making money.

**When this applies:** Before starting any new business unit or product line.
Every project should trace back to the vision. If it doesn't contribute, it
shouldn't exist.

---

## Layer 2: Mission (decade)

A bold, concrete, decade-long goal. Collins calls this a BHAG — Big Hairy
Audacious Goal. It's measurable and has a finish line.

Source: Jim Collins, *Built to Last* — the envisioned future that galvanizes
effort.

**When this applies:** Before defining product strategy. The mission constrains
which products to build and which markets to enter.

---

## Layer 3: SMAC Recipe

A set of durable operating practices — Specific, Methodical, And Consistent.
The SMAC recipe defines how the organization operates regardless of market
conditions. It changes rarely (years, not quarters).

Source: Jim Collins, *Great by Choice* — the disciplined consistency that
separates 10X companies from comparison companies.

**When this applies:** Before defining processes, hiring criteria, or
operational practices. The SMAC recipe is the constitution.

---

## Layer 4: Product-Led OKRs (quarterly)

A product-led organization where quarterly Objectives and Key Results drive
all work. Every team member knows their OKR and how their work connects to it.

Source: John Doerr, *Measure What Matters*; Jesper Jurcenoks, *P4-90 and OKR*
whitepaper.

**When this applies:** At the start of every quarter. OKRs define what success
looks like for the next 90 days.

---

## Layer 5: Three Key Results per OKR

Each OKR has exactly three Key Results, covering three dimensions:

| # | Dimension | Measures | Example |
|---|-----------|----------|---------|
| 1 | **Quantity** | How much | "Process 10,000 specs per month" |
| 2 | **Quality** | How well | "< 2% error rate on generated tests" |
| 3 | **Efficiency** | How fast/cheap | "Average generation time < 30 seconds" |

Each Key Result has a crisp, measurable KPI — no ambiguity, no subjective
assessment. If you can't measure it, it's not a Key Result.

**When this applies:** When defining OKRs. Reject any Key Result that doesn't
have a concrete number attached.

---

## Layer 6: Metric-Driven Development

Use a Build-Measure-Learn cycle (Lean/Agile) to move the KPI. The KPI must
be calculated daily and visible to everyone on the team.

**The critical principle:** Without a daily-calculated KPI where everyone on
the team can see their effort quickly reflected in the metric, there is no
feedback loop. Work becomes disconnected from outcomes. The absence of visible
metrics leads to politicizing of the workplace — decisions get made by opinion
and seniority instead of data.

**When this applies:** Every sprint. Every feature. Before writing code, ask:
"Which KPI does this move, and how will we measure the change?"

---

## Layer 7: Behavior-Driven Development (BDD)

Define product behavior in structured Gherkin scenarios before implementation.
Behaviors are organized hierarchically: Capability > Feature > Behavior.

Each behavior is a contract: Given [context], When [action], Then [outcome].
Stakeholders can read and validate behaviors without reading code. The spec
is the single source of truth for what the product does.

**When this applies:** Before writing any feature code. Define the behavior
in LeanSpecs first, get stakeholder agreement, then implement.

---

## Layer 8: API First, then CLI, then GUI

Build in this order:

1. **API** — the core contract. Every capability is an API endpoint first.
   Other programs, agents, and services can integrate immediately.
2. **CLI** — batch file integration, scripting, easy calls from other programs.
   The CLI is a thin wrapper around the API.
3. **GUI** — a mobile-friendly Web UI. The GUI calls the same API. It's the
   last thing built, not the first.

**Why this order:** APIs have the highest option value. A GUI without an API
is a dead end. An API without a GUI is still useful to every developer, agent,
and automation in the ecosystem.

**When this applies:** When designing any new service or feature. Start with
the API contract (OpenAPI spec or MCP tool definition), build the CLI, then
add the web UI.

---

## Layer 9: Primitives Over Frameworks

Build primitives — small, composable, single-purpose components. Not frameworks
that lock users into a specific way of working.

Primitives have higher option value. A framework constrains the future. A
primitive can be composed into any framework. When the stdlib has a clean
solution, use it instead of hand-rolling the equivalent.

Source: jjstack coding DNA, Section 2.

**When this applies:** Every architecture decision. Every abstraction. Ask:
"Am I building a primitive that others can compose, or a framework that forces
a specific workflow?"

---

## Layer 10: Test-Driven Development (TDD)

Write the tests first. Watch them fail. Then write code until they pass.

The tests are derived from the Gherkin behaviors (layer 7). The test file
structure mirrors the behavior hierarchy. Each test traces to a behavior ID.

**The cycle:**
1. Write test from Gherkin scenario
2. Run test — it fails (red)
3. Write minimum code to pass (green)
4. Refactor (clean)
5. Commit

**When this applies:** Every implementation task. No code without a failing
test first. Use `/unit-test-builder` to generate test suites from LeanSpecs
behaviors.

---

## Layer 11: Coding DNA

The specific coding standards, patterns, and anti-patterns that govern how
code is written. Variable naming, error handling, file structure, comment
style, import order, block-end markers.

Source: `~/.claude/skills/jjstack/references/coding-dna.md`

**When this applies:** Every line of code. Load the coding DNA before writing
or reviewing any code.

---

## How the layers connect

```
Vision (century)
  └─ Mission (decade)
       └─ SMAC Recipe (years)
            └─ OKRs (quarterly)
                 └─ Key Results: Quantity / Quality / Efficiency
                      └─ KPIs (daily measurement)
                           └─ Behaviors (BDD specs)
                                └─ API → CLI → GUI
                                     └─ Primitives (composable)
                                          └─ Tests first (TDD)
                                               └─ Code (DNA)
```

Each layer answers a different question:

| Layer | Question |
|-------|----------|
| 1. Vision | Why do we exist? |
| 2. Mission | Where are we going this decade? |
| 3. SMAC | How do we operate? |
| 4. OKRs | What matters this quarter? |
| 5. Key Results | How do we measure success? |
| 6. KPIs | Are we moving the needle today? |
| 7. BDD | What should the product do? |
| 8. API first | In what order do we build? |
| 9. Primitives | What kind of components do we build? |
| 10. TDD | How do we verify it works? |
| 11. Coding DNA | How do we write the code? |
