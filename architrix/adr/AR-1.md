---
id: AR-1
title: Sibling skills share one base reference; each skill owns only its ending
status: accepted
spec_refs: []
paths: ["references/memory-sweep.md", "skills/save-and-clear/SKILL.md", "skills/save-and-exit/SKILL.md", "bin/jjstack-verify-skills"]
supersedes: null
superseded_by: null
created: 2026-07-16T22:46:02+00:00
updated: 2026-07-16T22:46:58+00:00
---

# AR-1: Sibling skills share one base reference; each skill owns only its ending

## Context

jjstack skills are prose instructions the model executes. /save-and-clear had grown to 427 lines, of which roughly 380 were a memory sweep (locate the project memory dir, dedup candidates, write files, update MEMORY.md, report) that had nothing to do with clearing. It was simply the durable-lesson extraction that must happen before ANY session boundary.

Adding /save-and-exit on 2026-07-16 forced the question. A literal copy, which is what "make an identical skill" invites, would have produced two ~400-line files sharing ~380 lines. Duplicated prose drifts: the next edit lands in one copy, the second rots silently because nobody remembers it exists, and there is no compiler to catch the divergence.

jjstack already had the mechanism: a top-level references/ directory of shared docs (quality-loop.md, memory-promotion.md, root-cause-analysis.md) that skills load by cat-ing the path under the jjstack skill root. That path resolves because the installed jjstack skill dir is a symlink to the repo root. The pattern existed; it had just never been applied to the save-and-clear family.

## Decision

When two or more skills differ only at the end, the shared body lives in exactly one file under references/, and each skill retains only the part that genuinely differs.

Applied to the save-and-clear family: references/memory-sweep.md owns steps 1 through 5a (the sweep, the dedup layers, the report shape, and the TM_WORKER_NAME probe). Each caller owns only its close, 5b and 5c. /save-and-clear files a QM resume order and restarts; /save-and-exit settles its QM ledger and exits. The base explicitly refuses to define a close and hands back to the caller.

Two constraints bind any such refactor:

1. Preserve the anchors dependents cite. Callers reference skills by exact string, not by import, so a rename breaks them with no error. /rollover cites save-and-clear's "step 5b"; /resume-from-clear matches the literal QM label "Resume after save-and-clear". Both were preserved and are now checked.

2. Guard the pointer. A skill that cats a base which does not exist fails SILENTLY: the model reads nothing and improvises, producing plausible output with the governing rules missing. bin/jjstack-verify-skills exists for this class, and also checks frontmatter/directory agreement, installed symlinks, and that a base has not been copy-pasted back into a caller.

## Consequences

Accepted:

- A fix to the sweep now fixes every caller at once. One place to edit, one place to be wrong.
- Adding a whole new skill came out net -109 lines.
- Reading a single skill no longer shows the whole procedure; the reader must follow the cat to the base. Mitigated by each skill naming the base at the top of its workflow and in its Iteration footer.
- Skills gain a load-order dependency: the base must be read before the close makes sense. If the base is unreadable the skill degrades quietly rather than erroring, which is why the verify script is not optional.
- bin/jjstack-verify-skills is new infrastructure in a repo that previously had no test suite. It is deliberately narrow, checking only machine-decidable invariants. An earlier draft keyed its copy-paste check on the reference H1 and produced false positives, because a skill may legitimately NAME a base (jj-qa's H1 mentions "QA Philosophy") without copying it. It now keys on a distinctive body marker.

Rejected: copying the file. It satisfies the literal request and guarantees drift.
