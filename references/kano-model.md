# Extended Kano Model — Steam Train

Functionality prioritization framework by Jesper Jurcenoks. Every feature gets
a kano_level 1–10 that determines QA depth, quality tolerance, and whether it
should exist. Two motions: fulfill the promise (bugs) or expand it (features).

**QA depths below are MINIMUMS — floors, not ceilings. Always strive higher.**

---

| Level | Name | Category | Steam Train | Min QA (floor) | Quality Tolerance |
|-------|------|----------|-------------|----------------|-------------------|
| 1 | **Security** | Must-Be | Boiler doesn't explode; brakes work | 100% use + 100% corner | Zero — disable if broken |
| 2 | **Core** | Must-Be | Haul a load forward | 100% use + 95% corner | Zero |
| 3 | **Auxiliary** | Must-Be | Reverse gear, couplings, tickets | 100% use + 75% corner | Broken 1–2 days ok |
| 4 | **Performance** | One-Dimensional | Speed, cargo capacity | Lab + production measurement | 10% dip, 2 weeks |
| 5 | **Bells & Whistles** | Attractive | Shiny bells that signal the train | 100% use + 50% corner | Broken 5 days ok |
| 6 | **Less is More** | Reverse | Remove smoking in compartments | Clutter regression tests | Quarterly review |
| 7 | **Me Too / Checkbox** | Indifferent | Heated waiting rooms | 100% use + 50% corner | MVP sufficient |
| 8 | **Nice to Have** | Indifferent | Timetables sorted alphabetically | 100% use + 50% corner | Low urgency |
| 9 | **Single Customer** | Indifferent/Reverse | Stop at Smith's Factory | 100% use cases | Kill when unused |
| 10 | **Show Horse** | Attractive → Reverse | Steam motorcycle — cool, useless | SME usefulness review | Kill it |

---

## Key principles

- **1–3 (Must-Be):** Customer never mentions it unless burned. Absence =
  cliff-drop in satisfaction. Presence = neutral. No praise, only complaints.
- **4 (Performance):** Main purchase/churn driver. Linear: more = better.
  Diminishing returns at the top.
- **5 (Attractive):** Customer didn't know they needed it. Wow + real utility.
  Even poor implementation impresses early adopters.
- **6 (Reverse):** Development effort is SUBTRACTION. Remove clutter, extra
  steps, wrong-option traps. Expanding the feature makes it worse.
- **7 (Checkbox):** Build MVP to check the RFP box. Improving beyond MVP = 
  zero return. Influences purchase, not churn.
- **8 (Nice to Have):** No buying/churning decision. Slight annoyance → slight
  happiness. Narrow satisfaction band regardless of effort.
- **9 (Single Customer):** +1 customer, −N customers. Kill when unused.
- **10 (Show Horse):** Evil twin of Bells & Whistles. All show, no work.
  Customers who discover the fraud turn hostile. Kill it.

**Behind the Scenes (honorable mention):** Invisible to customers. Internal
ops, cost reduction. QA as needed. No satisfaction impact.

---

## Feature lifecycle

```
New feature:   B&W → Performance → Basic Requirement → Less is More
Competitor's:  Show Horse → Nice to Have → Me Too → Less is More
```

---

**Remember:** Kano level sets the MINIMUM test investment. A Kano 8 feature
that gets thorough testing is a bonus, not a violation. Never skip a test
because "the Kano level says we don't need it." The table tells you the floor
— your job is to build above it.
