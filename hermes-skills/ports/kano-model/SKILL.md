---
name: kano-model
description: >
  Load the 10-level Extended Kano Model (Steam Train). Injects the full
  prioritization framework so every feature justifies its existence, QA depth,
  and quality tolerance. Use when prioritizing features, setting QA depth,
  reviewing specs, or deciding what to build/kill. Trigger on: "kano model",
  "kano level", "feature priority", "what kano", "steam train", "QA depth",
  "quality tolerance", "should we build this".
allowed-tools:
  - Read
  - Bash
---

# Extended Kano Model — Steam Train

Load and apply the 10-level functionality prioritization framework.

After loading, identify which Kano level applies to the current feature and
use it to determine minimum QA depth, quality tolerance, and whether the
feature should exist. QA depths are MINIMUMS — always strive higher.

## The 10-Level Extended Kano Model

| Level | Name | Description | QA Depth | Quality Tolerance |
|-------|------|-------------|----------|-------------------|
| 1 | Security | Non-negotiable safety/security requirements | Exhaustive | Zero |
| 2 | Core | Must-have features without which product fails | Full regression | Near-zero |
| 3 | Aux | Expected supporting features | Standard | Low |
| 4 | Performance | Features that delight when fast/smooth | Performance testing | Medium |
| 5 | Bells & Whistles | Nice-to-haves that surprise and delight | Smoke | Medium-high |
| 6 | Differentiation | Features that set you apart from competitors | Targeted | Medium |
| 7 | Integration | Connects to other tools/workflows | Integration testing | Medium |
| 8 | Personalization | User-specific customization | Sample testing | Higher |
| 9 | Innovation | Novel capabilities users didn't know they wanted | Prototype | High |
| 10 | Foundation | Infrastructure enabling all other levels | Infra testing | Varies by layer |

## Usage

When assessing a feature or task:

1. Identify the Kano level (1-10)
2. Apply the minimum QA depth for that level
3. Apply the quality tolerance — zero tolerance means no known defects land
4. Use the level to prioritize: lower Kano numbers block higher ones
5. Use the level to kill features: if a level-8 feature competes with a level-2 gap, fix the gap first

## Prioritization rules

- Security (1) is never negotiable — no feature ships that violates it
- Core (2) bugs block all other work
- Build in ascending order when resources are constrained
- "Should we build this?" — if you can't place it on the model, you haven't understood it yet
- Foundation (10) is appended last in any priority list despite its enabling role

## Attribution

Adapted from jjstack/kano-model (Extended Kano Model, Steam Train variant).
