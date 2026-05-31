---
name: groom
version: 0.1.0
description: |
  Groom memories or skills to remove sprawl: vector-cluster near-duplicates,
  propose merges, human-review each one, apply, DNA-tighten survivors,
  re-index. One operation, three sub-modes - memory, skills, or all.
  The "all" mode adds the graduation ladder: procedure memories used
  frequently can be proposed for promotion to skills, and rule memories
  for promotion to CLAUDE.md.
  Trigger on: "/groom", "groom memory", "groom skills", "groom all",
  "memory cleanup", "consolidate memories", "dedup memories",
  "memory grooming", "skill consolidation", "graduation pass".
  Do NOT trigger for: routine save-and-clear writes (use /save-and-clear),
  one-off memory edits (just Edit the file), or anything destructive
  without explicit user invocation. This skill is destructive on apply -
  it requires backups and human review at every merge.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - Edit
  - Write
  - Agent
---

# /groom - vector-cluster, propose, review, apply

Single entry point for memory and skill consolidation. The operation is
identical for both targets: embed every entry, cluster near-duplicates
by similarity, propose merges, human reviews each one, apply approved
merges, DNA-tighten survivors, re-index. Only the storage adapter
differs.

**Destructive on apply. Backups mandatory before any merge.**

## Modes

```
/groom memory [--slug <project-slug>] [--threshold 0.85] [--ingest]
/groom skills [--threshold 0.90]
/groom all
```

- **`memory`** - Groom one project's curated `~/.claude/projects/<slug>/memory/`
  files via gbrain similarity. Default threshold 0.85.
- **`skills`** - Groom the skills index (gstack-owned skills are read-only;
  jjstack-owned and custom only). Default threshold 0.90 (skills are
  riskier to merge than memories). **Council-deferred** until skill-miss
  telemetry confirms the router need; specced here but recommend manual
  review pass first.
- **`all`** - Memory + skills together AND the graduation ladder. Only
  this mode sees both gbrain pools plus the use-frequency log
  (`~/.jjstack/skill-misses.jsonl`, recurrence_count fields), so only it
  can propose graduations across the memory to skill to CLAUDE.md
  boundary.

### Default scope = current worker's own project

`--slug` defaults to the current cwd's project slug. The "Over-reach"
rule in `~/.claude/CLAUDE.md` says each worker grooms only its own
memories - so the safe path is the default. Derive the slug from cwd:

```bash
pwd | sed 's|^/|-|; s|/|-|g'
# /home/jesper/PycharmProjects/jjstack → -home-jesper-PycharmProjects-jjstack
```

When the user invokes `/groom memory` with NO `--slug` flag, the skill
uses this derived slug. No surprise cross-project grooming.

### Cross-slug invocations require explicit confirmation

If `--slug <X>` names a project whose memory dir is NOT the cwd's, the
skill MUST:

1. Print a warning naming both slugs ("you are in PROJECT A but
   grooming PROJECT B's memories").
2. Cite the over-reach rule from CLAUDE.md.
3. Use AskUserQuestion to require explicit "yes, groom B from A"
   confirmation.
4. Only proceed on explicit approval.

The mechanism allows it (sometimes there is a legitimate reason - e.g.
an orchestrator running `/groom` on a worker's memory). The policy
lives in CLAUDE.md. This step makes the boundary visible at
invocation, so over-reach is never accidental.

## Mandatory pre-steps

1. **Load the promotion philosophy** so graduation decisions match the
   shape x frequency ladder:

   ```bash
   cat ~/.claude/skills/jjstack/references/memory-promotion.md
   ```

2. **Check the PHI / no-gbrain opt-out marker for the target slug**:

   ```bash
   MEM_DIR="$HOME/.claude/projects/<slug>/memory"
   [ -f "$MEM_DIR/.no-gbrain" ] && echo "OPTED_OUT (no-gbrain file)"
   grep -lE '^sensitivity:[[:space:]]*phi' "$MEM_DIR"/*.md 2>/dev/null | head -1 && echo "OPTED_OUT (sensitivity: phi)"
   ```

   If EITHER marker is present, this slug is opted out of gbrain (per
   `~/.claude/CLAUDE.md` "Sensitive data stays off the shared index").
   Skip step 3 below; use the **No-gbrain native fallback** mode (see
   that section). The bridge will refuse to ingest this slug; do not
   try to bypass.

3. **Confirm gbrain is installed and reachable** (only for non-opted-
   out slugs):

   ```bash
   command -v gbrain && gbrain doctor --fast --json 2>&1 | jq -r '.engine, .pages'
   ```

   If gbrain is absent AND the slug is NOT opted out: stop and report
   `BLOCKED - gbrain not installed. Run /setup-gbrain --pglite first,
   OR mark this slug opted-out if it carries sensitive data.`

   If gbrain is absent AND the slug IS opted out: that is the expected
   path. Proceed via the no-gbrain native fallback.

4. **Confirm the bridge has already populated gbrain** for the target
   slug (gbrain mode only). If not, the skill calls
   `jjstack-memory-bridge --slug <slug> --ingest` before clustering.

5. **Mandatory backup** before any apply step. The skill creates a
   timestamped snapshot of the target directory under
   `~/.jjstack/backups/<target>-<YYYYMMDD-HHMMSS>/`. Without a successful
   backup, apply is blocked. Applies to both gbrain and native modes.

## No-gbrain native fallback

When the target slug is opted out of gbrain (PHI marker present) OR
gbrain is unavailable AND the user explicitly authorizes a native
groom, the skill switches to a local-only path that never reads or
writes the shared index.

### Phase 1 (native) — Discover clusters

Read all memory files in `~/.claude/projects/<slug>/memory/*.md`
directly. Pick clustering method by corpus size:

- **<= 20 entries**: model-judgment clustering. Read all entries into
  context, propose near-duplicate pairs based on topical overlap. No
  external embedding service involved.
- **> 20 entries**: lexical similarity. Compute a TF-IDF or Jaccard
  similarity matrix over `title + body` tokens. Threshold same as
  gbrain mode (0.85 for memory, 0.90 for skills).

Either path produces the same cluster artifact — a list of file
groups that are candidates for merge.

### Phases 2-5 (native) — Same flow

Propose, human-review, apply, DNA-tighten exactly as in gbrain mode.
The artifacts (`~/.jjstack/groom-proposals/<target>-<date>.md`,
backups, applied merges) are identical.

### Phase 6 (native) — Rebuild MEMORY.md only

Re-derive `MEMORY.md` from the surviving memory files. **No bridge
call. No gbrain put. No --sync.** The slug remains native-only by
design.

```bash
# Example MEMORY.md rebuild — sketch only; the model fills in headings
# and one-line hooks per the file's name/description frontmatter.
ls ~/.claude/projects/<slug>/memory/*.md
```

The native path produces no gbrain side effects. If gbrain later
becomes available AND the project removes its opt-out marker, the
user can manually invoke the bridge — never automatic.

## The shared algorithm

### Phase 1 - Discover

For each entry in the target corpus:
- For memory: list pages with `gbrain list --tag "project:<slug>"`
- For skills: list jjstack-owned + custom skill SKILL.md files
  (provenance guard: skip anything that lives under
  `~/.claude/skills/gstack/` or inside an Anthropic plugin path - those
  get clobbered on upgrade)

For each entry, query gbrain for nearest neighbors:
- `gbrain query "<entry-title-or-content-snippet>" --json`
- Take results with similarity >= threshold (excluding the entry itself)

Build clusters by union-find: any two entries that score above
threshold join the same cluster. Output: a list of clusters, each with
2+ entries.

### Phase 2 - Propose

For each cluster of size 2+:
- Read all entries' full content
- Identify the canonical entry (highest recurrence_count, or longest
  content, or most recent - heuristic, documented per cluster)
- Draft a merged version (or recommend "leave alone" if the entries
  are topically similar but functionally different - the qa-loop /
  qa-review / jj-qa case)
- Write a proposal block to
  `~/.jjstack/groom-proposals/<target>-<YYYYMMDD>.md` with:
  - cluster members (file paths + similarity scores)
  - reasoning (true duplicate? differentiated? graduation candidate?)
  - proposed action: merge / leave / promote-to-skill / promote-to-claude-md
  - merged content draft (for merge actions)

### Phase 3 - Human review

Present the proposal file to the user. Use AskUserQuestion per cluster:
- Approve the merge as drafted
- Reject (leave entries alone)
- Modify (user edits the merged content, then approve)
- Promote instead (if the cluster is one entry being graduated, not
  multiple being merged)

The default framing is "distinguish or merge?" not "merge or skip?" -
biasing toward preservation. **Anchoring bias is real**; the user is
not pressured to approve.

### Phase 4 - Apply (destructive)

For each approved cluster:
- Write the merged entry to the canonical path (memory file or SKILL.md)
- Delete or flag-as-`promoted: true` the non-canonical source entries
- Update `MEMORY.md` index lines for removed entries
- For graduations: create the new skill SKILL.md and symlink, OR
  append the new rule to CLAUDE.md (with user explicit approval - the
  to-CLAUDE.md promotion is always manual)

### Phase 5 - DNA-tighten

Run the canonical writing-DNA over each survivor's description / body:
- Canonical source: `/home/jesper/PycharmProjects/jesper-jurcenoks-ai-personalizations/voice-dna/Jesper Jurcenoks Voice DNA Final.md`
- Conclusion first, no pleonasm, short-dash not emdash, every sentence
  earns its place
- For skill descriptions: also add "Do NOT trigger for" boundaries
  naming the closest sibling skills

### Phase 6 - Re-index AND orphan-purge

Re-run the bridge with `--sync` so gbrain reflects the post-groom
state, then re-extract the trigger index:

```bash
~/.claude/skills/jjstack/bin/jjstack-memory-bridge --slug <slug> --ingest --sync
~/.claude/skills/jjstack/bin/jjstack-extract-triggers
```

`--sync` is mandatory here, not optional. Every groom that deletes,
merges, or renames a memory leaves orphan gbrain pages whose source
file is gone - `--ingest` alone is upsert, not true sync. The orphans
pollute query/similarity results until purged. `--sync` diffs the
current put-set against gbrain's `project:<slug>` page list and
deletes the difference. (Surfaced by iris-qa-tm during its post-groom
cleanup: 11 hand-purged orphans before this was baked into the skill.)

Update `MEMORY.md` to reflect retired entries.

## Per-type adapters

### memory adapter

- Store: gbrain pages tagged `project:<slug>`
- Threshold default: 0.85
- Extra step: `ecosystem:` tag promotion. After merge, ask whether the
  surviving memory is cross-cutting enough to also tag
  `ecosystem:disciplin-run` (or another ecosystem).
- Extra step: procedural-memory to skill spinout. If the merged entry
  reads as a procedure (Given/When/Then-shaped, or "how to do X"
  steps), flag for graduation in `all` mode.

### skills adapter

- Store: gbrain pages tagged `kind:skill` (or a separate skills-brain
  if available - gbrain v0.18 supports a second engine via
  `GBRAIN_DATABASE_URL` override). Fallback: tag-filtered single
  brain.
- Threshold default: 0.90 (higher than memory; skills are riskier to
  merge because they encode workflow, not just facts)
- Provenance guard: never edit gstack/GSD/plugin skills in place. Wrap
  or suppress via the jjstack symlink layer instead.
- Never merge away a skill with high `success_count` (per
  `~/.jjstack/skill-misses.jsonl` confusion matrix). Those skills are
  earning their existence; they're not duplicates.

### all adapter (graduation ladder)

When `--all` is set, after memory and skills are independently
groomed, run the graduation pass:

- **memory to skill candidates**: a procedural-shaped memory whose
  `recurrence_count >= 3` and `last_seen` spans 2+ sessions. Propose
  spinning it out as a new SKILL.md, with the memory body becoming
  the skill instructions.
- **memory or skill to CLAUDE.md candidates**: an always-needed rule.
  Surface as a candidate; do NOT auto-promote - CLAUDE.md stays
  manual per the memory-promotion convention.
- **skill retirement**: a skill that has not been invoked in the
  miss-detect telemetry window AND has zero high-`success_count`
  signal can be a retirement candidate.

## Self-test on jjstack memory

Before running against any large corpus, verify the skill works on
jjstack's own ~5 memory files. Expected outcome with default
threshold 0.85: **no clusters propose merges** (these memories cover
different topics). The skill should report "no merges to propose" and
exit cleanly.

```
/groom memory --slug -home-jesper-PycharmProjects-jjstack --threshold 0.85
```

If the self-test produces unexpected merges, raise the threshold or
fix the proposal logic before running on a larger corpus.

## Verification

| Check | Pass condition |
|-------|---------------|
| gbrain reachable | `gbrain doctor` returns engine + page count |
| Backup created | `~/.jjstack/backups/<target>-<timestamp>/` exists with all source files |
| Clusters detected | proposal file lists 0+ clusters with similarity scores |
| Human review fires | AskUserQuestion runs for each cluster (or "no clusters" message) |
| Apply only on approval | unapproved clusters leave files unchanged |
| Re-index passes | `gbrain list` returns the new state; `skill-triggers.json` rebuilt |

## Important rules

- **Destructive on apply. Backup mandatory.** Without
  `~/.jjstack/backups/<target>-<timestamp>/` populated successfully,
  the apply step is blocked.
- **Human review at every merge.** No batch-approve. Anchoring bias
  is real; the default framing biases toward preservation, not
  merging.
- **Provenance guard for skills.** Never edit gstack/plugin SKILL.md
  files in place. They get overwritten on upgrade.
- **Graduation to CLAUDE.md stays manual.** The skill surfaces
  candidates; the user does the move.
- **Self-test before any large-corpus run.** Validate the threshold
  and proposal logic on jjstack's own ~5 memories first.
- **One target per invocation.** `/groom memory` operates on one slug
  at a time. `/groom skills` is jjstack+custom only. `/groom all` is
  the cross-cutting graduation pass - never mix scopes.
- **Council-defer status of `/groom skills`:** the council
  recommended measuring before mechanizing. Until the skill-miss
  telemetry shows a HOT cluster (>=10 misses in 24h concentrated in
  <=5 skills, >=70% share), prefer description tightening (already
  shipped for the QA + /review clusters) over running `/groom
  skills`. The skill stays available for explicit invocation.
- **PHI / sensitive data NEVER touches gbrain.** Opt-out markers
  (`.no-gbrain` file or `sensitivity: phi` frontmatter) take the slug
  through the native fallback path. The bridge refuses opted-out
  slugs with exit 4 — defense in depth so a PHI bridge cannot happen
  by accident. Per `~/.claude/CLAUDE.md` "Sensitive data stays off
  the shared index."

## Data flow

```
~/.claude/projects/<slug>/memory/*.md     (sources)
            |
            v  jjstack-memory-bridge --slug <slug> --ingest
~/.gstack/projects/<slug>/learnings.jsonl (intermediate)
            |
            v  gbrain put (per entry)
gbrain pages tagged project:<slug>        (index)
            |
            v  /groom memory --slug <slug>
~/.jjstack/groom-proposals/memory-<slug>-<date>.md
            |
            v  human review
applied merges -> updated SKILL.md or memory files
            |
            v  Phase 6 re-index --ingest --sync
gbrain + skill-triggers.json reflect new state
            (orphan pages from renamed/merged/deleted sources are purged)
```

## What this skill does NOT do

- It does NOT run automatically. Manual invocation only.
- It does NOT decide what's a duplicate without human review. Vector
  similarity is a candidate generator, not a merge decider.
- It does NOT touch gstack/plugin skills. Provenance guard.
- It does NOT promote anything to CLAUDE.md without explicit user
  approval.
- It does NOT run `/groom skills` based on vibes - wait for telemetry
  evidence per the council's deferral.
