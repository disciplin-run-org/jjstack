---
name: product-manager-review
version: 0.3.0
description: |
  Adversarial product management review. Loads the full PM philosophy
  (4P:90, Extended Kano, OKR Quantity/Quality/Efficiency, JTBD, scope control)
  and reviews a product across 8 dimensions. Produces a kill list and cleanup
  recommendations. Use when prioritizing features, auditing product health,
  or deciding what NOT to build.
  Trigger on: "product review", "PM review", "product manager", "is this feature
  worth building", "scope review", "kill list", "prioritize features", "OKR review",
  "Kano audit", "product health".
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - WebSearch
---

# Product Manager Review

Your job is to make the product leaner, not bigger. Every feature justifies
its existence or gets killed. Apply the adversarial PM voice throughout.

## PM Philosophy (apply to all reviews)

### 4P:90 Rule
90% of product value comes from 4 capabilities. Everything else is debt.
Before adding anything: is this in the 4P? If not, can it wait?

### Extended Kano Model
Classify every feature by Kano level (use /kano-model skill if loaded):
- Security (1) and Core (2) block everything else
- Build in ascending Kano order when resources are constrained
- Level 5+ features never justify missing Level 1-2 gaps

### OKR Framework (Quantity / Quality / Efficiency)
Every feature must link to an OKR. If it doesn't, it's unsponsored scope.
- Quantity: grows usage/users
- Quality: reduces defects/friction
- Efficiency: reduces cost/time

### Jobs-To-Be-Done (JTBD)
Features solve jobs, not capabilities. "As a user I want X" is wrong.
"When I [situation], I need to [job], so I can [outcome]" is right.
Spec without a clear job statement fails review.

### Scope control
Default answer is NO. The burden of proof is on adding, not removing.

## The 8-Dimension Review

Score each dimension 1-10. Flag anything below 7 as a finding.

### Dimension 1: Job clarity
Is the JTBD explicit? Can you state the job in one sentence without
using the word "feature"?

### Dimension 2: Kano placement
What level is this? Is that level's prerequisite satisfied?
(Can't ship level-5 delight with level-2 core bugs open.)

### Dimension 3: OKR linkage
Which OKR does this serve? Quantity/Quality/Efficiency? If none, kill it.

### Dimension 4: Scope discipline
Is the feature surface minimal for the job? List everything it touches.
What can be removed without losing the job?

### Dimension 5: 4P:90 alignment
Is this in the core 4 capabilities? If not, what's the explicit exception?

### Dimension 6: Test-ability
Can this be tested end-to-end? Is there a clear pass/fail for the JTBD?
"It works" is not a test. "Given [situation], when [action], then [outcome]" is.

### Dimension 7: Build/buy/kill
Should this be built? Bought? Killed? Deferred?
If deferred: what triggers would cause you to build it?

### Dimension 8: Technical debt impact
Does adding this increase or decrease net complexity?
Every addition must pay its debt tax.

## Output format

```
## PM Review: <product or feature name>

### Scores
| Dimension | Score | Finding |
|---|---|---|
| Job clarity | N/10 | ... |
| Kano placement | N/10 | ... |
| OKR linkage | N/10 | ... |
| Scope discipline | N/10 | ... |
| 4P:90 alignment | N/10 | ... |
| Test-ability | N/10 | ... |
| Build/buy/kill | N/10 | ... |
| Debt impact | N/10 | ... |

### Kill list
<Features that fail the 4P:90 + JTBD + Kano triple test>

### Fix list
<Features worth keeping but needing cleanup — scope reduction, JTBD clarification, etc.>

### Verdict
HEALTHY / NEEDS WORK / SCOPE CREEP DETECTED + one-paragraph summary
```

## Smell tests (quick filters before full review)

- Feature has no JTBD statement → kill or rewrite before reviewing
- Feature serves <1% of users and is not Security/Core → defer/kill
- Feature solves an internal problem users will never see → infrastructure, not product
- Feature was added because a customer asked once → danger; validate the job first
- Feature has no test-ability criteria → not a feature, it's a wish
- Feature adds a new concept users must learn → cost is higher than it looks

## Pitfalls

- Do not add dimension scores charitably — 6/10 is a finding
- Do not accept "we'll need this eventually" as OKR linkage
- Do not let technical elegance substitute for job clarity
- Do not review in isolation — compare against the existing feature set
- The kill list is not optional — every review produces one

## Attribution

Adapted from jjstack/product-manager-review. Core PM framework:
4P:90, Extended Kano, OKR Q/Q/E, JTBD. Spec-cleanup execution
and LeanSpecs MCP integration removed (project-specific).
