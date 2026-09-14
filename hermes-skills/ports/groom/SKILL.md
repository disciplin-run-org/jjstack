---
name: groom
version: 1.0.0
description: |
  Groom memories or skills to remove sprawl: manually review near-duplicates,
  propose merges, human-review each one, apply. Three sub-modes — memory,
  skills, or all (memory then skills). Use when memory or skill list has grown
  unwieldy. Trigger on: "groom my memories", "groom skills", "groom all",
  "clean up memories", "deduplicate skills", "merge duplicate memories",
  "prune stale skills".
tags: [memory, skills, grooming, maintenance, deduplication]
---

# groom — Remove sprawl from memories and skills

Use when the user wants to clean up memories or skills, merge near-duplicates,
or prune stale entries.

## Sub-modes

- **memory** — groom the Hermes memory store (user profile + personal notes)
- **skills** — groom the installed skills list (find overlapping/redundant skills)
- **all** — run memory then skills in sequence

## Process

### 1. List candidates
- **memory**: read full memory (both user profile and personal notes sections)
- **skills**: list all skills with descriptions via skills_list

### 2. Cluster near-duplicates
Group entries that cover the same topic. Look for:
- Same subject, different wording
- One entry that fully subsumes another
- Contradicting entries (keep newer/more specific)
- Stale entries (facts no longer true or relevant)

Similarity threshold guidance:
- Memory: flag pairs >80% topically overlapping
- Skills: flag skills whose descriptions AND trigger conditions overlap significantly

### 3. Propose merges/deletions
For each candidate cluster, propose one of:
- **MERGE**: combine into one tighter entry (show the proposed merged text)
- **SUPERSEDE**: keep the better one, drop the weaker (show which and why)
- **PRUNE**: drop entirely (stale, no longer accurate)
- **KEEP**: no action needed

Present all proposals as a numbered list. Stop and show to user before applying anything.

### 4. Human review
Show each proposal. User confirms, rejects, or edits. Only apply after explicit approval.

### 5. Apply
- Memory merges/prunes: use memory tool with operations batch (replace/remove)
- Skill merges: skill_manage patch/edit the surviving skill, then delete the absorbed one
  - Pass absorbed_into=<umbrella> when deleting a merged skill
  - Pass absorbed_into="" when pruning with no forwarding target
- Check if any cron jobs reference a skill before deleting it

### 6. Report
Summarize: N merged, N pruned, N kept. Note before/after counts.

## Pitfalls

- Never apply without human review of each proposal
- Check cron jobs before deleting any skill by name
- Memory is injected every turn — merged entries must be shorter than sum of parts
- Skills with different trigger conditions may look similar but serve different purposes
- When in doubt, keep both and note the ambiguity rather than merging incorrectly
- User profile memory and personal notes memory are separate — groom each independently
