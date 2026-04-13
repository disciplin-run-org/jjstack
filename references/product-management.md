# Product Management Philosophy

The backbone of PM knowledge for the dev ecosystem. Combines Jesper's
proprietary frameworks (4P:90, Extended Kano, OKR Quantity/Quality/Efficiency)
with industry best practices (JTBD, RICE, Lean). Every product in the
ecosystem is reviewed against this philosophy.

---

## 1. The PM Mindset — Adversarial Lean Thinking

Your job is to kill features, not add them. Scope is defined by what you
choose NOT to ship.

- Every feature must justify its existence with three things: an OKR link,
  a Kano level, and a customer job-to-be-done
- If a feature can't articulate its KPI impact in one sentence, it shouldn't
  exist
- "Less is More" (Kano level 6) is the most underused PM tool — actively
  removing functionality that subtracts value
- The PM who ships 5 features and kills 10 did more for the product than
  the PM who shipped 15 and killed none
- Scope creep is not a force of nature — it's a failure of discipline

**The lean test:** For every proposed feature, ask: "What is the simplest
version that moves the KPI?" Ship that. Measure. Decide if more is needed.
Most of the time, it isn't.

---

## 2. 4P:90 Framework

Goal setting and tracking framework. Designed by CEO Bob Lyons at Alert Logic
(2019), refined by Jesper Jurcenoks. The name: 4 P's (Plan, Progress,
Performance, Problems) in 90-day quarterly sprints.

Source: Jesper Jurcenoks, *4P:90 Setting Your Own Goals and Tracking Them*.

### Plan — 3 OKRs per Quarter

Pick the 3 most important improvements for the quarter. Not day-to-day work
— improvements that change the trend of a KPI.

**OKR format:** Objective (what are we trying to achieve?) + Key Result
(goal + measurement). The objective is lofty and inspirational. The key
result is crisp and measurable.

**"An OKR is the focused effort to change the trend of a KPI."** — Felipe
Castro. This is the single most important sentence in goal-setting. KPIs
exist permanently. OKRs are the quarterly push to move one.

**OKRs are stretch goals, not SMART goals.** Stretch goals inspire thinking
big — we know the outcome but not the path. Creativity required. In
hindsight, a stretch goal looks like a SMART goal because the path becomes
obvious.

**Measure outcomes, not work done.** "Hold weekly meetings" is work.
"Close 10% more deals" is an outcome. It's better if it took little work
to achieve the outcome. Alert Logic is outcome-driven.

**Picking the 3:** Business alignment (which aligns with company goals?),
sequencing (which is easier after X is in place?), diminishing returns
(which has the most improvement available for least effort?), carry-forward
(don't automatically carry a missed OKR — ask if another would see bigger
improvement).

**If you run out of ideas:** Think of Quality, Quantity, and Efficiency.
Let them balance each other.

### Progress — Qualitative Accomplishments

Recent accomplishments and upcoming next steps. Free text. Updated weekly
for 1:1 with manager.

### Performance — KPI Tracking

Track at least all KPIs referenced by OKRs. Three measurement points
(style depends on KPI type):
- **Cumulative:** MTD, QTD, YTD (sales, financial)
- **Point-in-time:** 2 months ago, 1 month ago, current (detection rates)

**"Fewer KPIs increases readability."** Less is More applies to dashboards
too. Non-tracked KPIs go to an addendum or live dashboard link.

### Problems — Risk Management

Top 2-3 items that could derail the plan. Each has:
- **Trigger event:** What would cause this problem?
- **Stage:** Monitor → Manage → Remediate (iceberg analogy)
- **Color code:** Green (on track) / Yellow (at risk) / Red (needs help)

### Cadence

| Frequency | Action |
|-----------|--------|
| **Daily** | Look at 4P:90, decide which OKR to move the needle on today |
| **Weekly** | Update for 1:1. Move accomplishments, add next steps, update KPIs |
| **Monthly** | Update monthly numbers, track against goals, record deviations |
| **Quarterly** | Set new theme and goals 2-4 weeks before quarter end. PDF old quarter |

---

## 3. OKR Structure — Quantity / Quality / Efficiency

Every OKR has exactly 3 Key Results, always covering these dimensions:

| KR | Dimension | Measures | Example |
|----|-----------|----------|---------|
| KR1 | **Quantity** | How much | "Process 10,000 specs per month" |
| KR2 | **Quality** | How good | "< 2% error rate on generated tests" |
| KR3 | **Efficiency** | How fast/cheap | "Average generation time < 30s" |

**Why three?** Covers all bases without dilution. Too many objectives = no
focus. These three dimensions balance each other: optimizing quantity alone
degrades quality; optimizing quality alone kills efficiency.

**Each KR has a crisp, measurable KPI.** No ambiguity, no subjective
assessment. If you can't measure it, it's not a Key Result.

**KPIs are calculated independently** (by Actuatrix in our ecosystem), never
self-reported. Self-reported metrics are vanity metrics.

**Efficiency is NOT AI-specific.** Whether the decision was algorithmic or
AI-powered doesn't matter. Efficiency = operations completed without human
intervention / total operations. Like Tesla's miles-per-disengagement.

**"An OKR without a daily-visible KPI is a wish, not a goal."** Without a
metric where everyone sees their effort reflected quickly, there is no
feedback loop. Work disconnects from outcomes. Decisions get made by opinion
and seniority instead of data.

---

## 4. Extended Kano Model — Feature Justification

Reference `/kano-model` for the full 10-level Steam Train framework.

**The PM's job:** Assign the correct Kano level to every behavior. This
determines QA depth, quality tolerance, build priority, and whether the
feature should exist at all.

**Active pruning:**
- Level 9 (Single Customer): kill as soon as usage drops
- Level 10 (Show Horse): kill immediately — all show, no work
- Features without a Kano level are unclassified scope — force a decision

**Less is More audit:** Quarterly review of UI clutter, extra steps to reach
core functionality, features that cause users to select wrong options. The
development effort here is subtraction, not addition.

**Feature lifecycle awareness:** Today's Bells & Whistles is tomorrow's
Basic Requirement. Plan for the evolution:
```
New feature:    B&W → Performance → Basic Requirement → Less is More
Competitor's:   Show Horse → Nice to Have → Me Too → Less is More
```

---

## 5. Jobs to Be Done (JTBD)

Customers don't buy products — they hire them to make progress in a specific
situation. The JTBD framework shifts focus from "what feature do they want?"
to "what are they actually trying to accomplish?"

Source: Tony Ulwick (Outcome-Driven Innovation), Clayton Christensen.

**Three dimensions of every job:**
- **Functional:** The practical task (process invoices, monitor servers)
- **Emotional:** How they want to feel (confident, in control, not anxious)
- **Social:** How they want to be perceived (competent, modern, responsible)

**The job stays stable even as solutions change.** "Get from A to B quickly"
has been solved by horses, trains, cars, and ride-sharing apps. The job
didn't change.

**Connects to Kano:** A feature's Kano level depends on how central it is
to the customer's core job. Core job = Kano 1-2. Supporting job = Kano 3.
Emotional delight = Kano 5. Unrelated to any job = Kano 9-10 (kill it).

**The JTBD litmus test:** "When [situation], I want to [motivation], so I
can [expected outcome]." If you can't fill this in for a feature, the
feature doesn't have a customer.

---

## 6. BDD Specification as PM Contract

The PM's primary output is not slides, not Jira tickets — it's Gherkin
specifications. Structured, machine-readable, stakeholder-validated.

Reference `/dev-philosophy` Layer 7.

**Hierarchy (each level constrains the next):**

| Level | Gherkin Type | Purpose | Example |
|-------|-------------|---------|---------|
| Capability | `Rule:` | System-level contract all children must follow | "Every spec mutation must be logged" |
| Feature | `Feature:` + As a/I want/So that | Integration test verifying children work together | User story with acceptance criteria |
| Behavior | `Scenario:` + Given/When/Then | Unit test for one specific requirement | One testable behavior |

**No child Gherkin can contradict its parent's contract.** This creates
machine-readable enforcement — stricter than natural language.

**The spec is the single source of truth.** If it's not in the Gherkin, it
doesn't exist. If the code doesn't match the Gherkin, the code is wrong.

---

## 7. Product Scaffold — Standard Structure

Every product follows the standard capability layout. Reference
`references/product-scaffold.md`.

| Cap | Name | Kano Range |
|-----|------|-----------|
| 1 | MCP Core | 1-2 |
| 2 | MCP Auxiliary | 3 |
| 3 | MCP Extended | 4-5 |
| 4 | Foundation (shared) | — |
| 5 | CLI Interface | 7 |
| 6 | Web UI | 5-8 |
| 10 | Technical Specs | — |
| 11 | Design System | — |

**"MCP is the product."** Every user action = MCP tool call. CLI wraps it.
Web UI calls the same tools. No behavior exists only in the GUI.

---

## 8. Build Order — API First, CLI, GUI

Reference `/dev-philosophy` Layer 8.

1. **API** — the core contract. Highest option value. Agents, scripts,
   integrations can use it immediately.
2. **CLI** — thin wrapper around the API. Batch integration, scripting.
3. **GUI** — mobile-friendly Web UI. Calls the same API. Built last.

**A GUI without an API is a dead end.** An API without a GUI is still useful
to every developer, agent, and automation in the ecosystem.

---

## 9. Scope Control — The Adversarial Toolbox

### RICE Scoring

Reach x Impact x Confidence / Effort = priority score. Best when you have
real user data. Forces quantification of gut feelings.

### Value vs Effort Matrix

Quick wins (high value, low effort) → do first.
Major projects (high value, high effort) → plan carefully.
Fill-ins (low value, low effort) → only if nothing better.
Time sinks (low value, high effort) → kill immediately.

### MoSCoW with Teeth

Must / Should / Could / Won't — but "Won't" means actively removed, not
"maybe later." A Won't that lingers is scope creep wearing a disguise.

### The 5 Whys of Scope

For every proposed feature:
1. Why does this feature exist?
2. Why does the customer need it?
3. Why can't they use an existing feature?
4. Why now (not next quarter)?
5. Why us (not a third-party integration)?

If any answer is weak, the feature is a candidate for the kill list.

### Kill Criteria

A feature should be killed or deferred if:
- It's a Show Horse (Kano 10) — all show, no work
- It serves a single customer (Kano 9) — and usage has dropped
- It has no OKR link — no one can say which KPI it moves
- It has no measurable KPI — can't tell if it's working
- It has negative Kano trajectory — becoming "Less is More"
- It fails the JTBD litmus test — no customer job
- RICE score is below threshold — low reach, low impact, high effort

---

## 10. Agentic Product Management (2026)

Products must be both human-usable AND agent-usable. The PM is becoming
"Manager of Robots."

**Machine-readable products:** MCP tools, OpenAPI schemas, structured
responses. An agent that can't discover and use your product is a customer
you've locked out.

**Goal vectors over user stories:** Instead of prescriptive "As a user I
want X," define the outcome: "Optimize checkout drop-off to < 20% within
7 days, max compute budget $500." Let the agent figure out how.

**Agent success metrics:**
- Task success rate (% of goals achieved without human intervention)
- Human intervention frequency (lower = better)
- User trust signals (does the human override the agent?)

**Every product in our ecosystem** exposes MCP tools as its primary
interface. CLI and GUI are convenience layers. The API is the product.
