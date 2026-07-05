---
name: investigate
version: 0.1.0
description: |
  Enhanced debugging — saves root cause analysis to repo, injects DNA.
  jjstack wrapper around gstack's investigate.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - WebSearch
  - Agent
  - Edit
  - Write
---

# jjstack investigate wrapper

Wraps gstack's `/investigate` with repo-local output and DNA injection.
All debugging insights go into the heal framework (per jjstack philosophy).

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

---

## Phase 1: Configure

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store: `OUTPUT_DIR`, DNA paths. Create output dir. Load DNA.

---

## Phase 2: Delegate to gstack

```bash
cat ~/.claude/skills/gstack/investigate/SKILL.md
```

Follow ALL instructions with:
- Output path override: `~/.gstack/projects/$SLUG/` → `{OUTPUT_DIR}`
- All diagnostic checks must go into the heal framework (check.py or heal.py), never ad-hoc
- All fixes must go into the heal framework, never one-off commands

---

## Phase 3: Post-enhancement

### 3.1 Framework integration

If a `debug/heal.py` exists in the project, ensure all new diagnostic checks and fixes discovered during investigation are added to the appropriate `test_<component>.py` scripts.

If no heal framework exists, suggest running `/heal` to create one.

### 3.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol.

### 3.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.

---

## Phase 4: Verified Contributing-Factors Tree

Load the jjstack RCA method and apply it on top of gstack's output.
This is the step that separates "found a plausible cause" from "found
the actionable root that prevents the class of failure."

```bash
cat ~/.claude/skills/jjstack/references/root-cause-analysis.md
```

Apply the four rules in order:

1. **Scope before explain** — write PROBLEM SCOPE with IS / IS NOT /
   STARTED before any causal reasoning. If gstack's investigation
   already produced causes without this scope, reconstruct the scope
   first and re-evaluate whether each claimed cause survives the
   IS-NOT filter. Apply **parsimony**: when a source of truth says X
   passes/works, that is your prior — overturn it only by reproducing X
   failing, never by inventing a second broken thing to preserve a
   first assumption.

2. **Every effect has at least two causes** (action + condition). If
   gstack produced a single-chain RCA, branch it into action and
   condition nodes. Any leaf that cannot be split this way is
   incomplete.

3. **Every claim carries evidence and confidence**. For each node in
   the tree, fill in `claim` / `evidence` / `confidence`. Evidence
   must be inspectable (log line, git-blame line, failing test, diff,
   reproducible command) AND the probe must be sound: **(3a)** a
   negative result (grep-miss, empty output) is the weakest evidence —
   run a positive control before it becomes a claim; **(3b)** read
   structured data through its consumer's parser (`json.loads`), never
   grep escaped/wire text. Anything without evidence is marked
   `hypothesis` — not allowed as a terminal stop, and **no downstream
   action** (work order, fix, spec edit, worker dispatch) may fire off a
   `hypothesis`-confidence root.

4. **Stop at the class boundary**. Write the regression test that
   would catch the CLASS of failure, not just this incident. Record
   it literally in the output. If you can't write the test, you
   haven't found the actionable root — keep going. If the failing
   artifact is *generated* (test ← Gherkin ← description), apply the
   "Generated-artifact bugs — climb the generation chain" section:
   fix the layer where the defect enters and regenerate downward until
   a test goes red on a real bug.

Write the resulting tree to `{OUTPUT_DIR}/rca-{YYYY-MM-DD}.md` in
the exact shape documented in `references/root-cause-analysis.md`:
`PROBLEM SCOPE`, `FAILURE` with action/condition branches, optional
AND-BRANCHES section for multi-cause conjunctions, and a `STOP CHECK`
section with the regression test plus class-boundary sentence.

If gstack's own investigation already reached an actionable root and
you can write the class-catching test, this phase formalizes the
output. If not, it surfaces the gap and continues the analysis.

### 4.1 Heal framework integration (revisited)

The regression test from STOP CHECK belongs in the heal framework.
If `debug/heal.py` exists, add the test there. If no heal framework
exists, suggest running `/heal` to create one — and include the
regression test as the first entry.

### 4.2 Promotion to memory

If this failure pattern has occurred before (check
`~/.jjstack/command-failures.jsonl` and any prior
`rca-*.md` in the repo), the pattern may be promotable to a
permanent rule per `references/memory-promotion.md`. Suggest
promotion when:

- The same action+condition combination has appeared 3+ times across
  2+ sessions, AND
- The class boundary is generalizable (not a single-function fix).

Do not promote automatically — surface the suggestion and let the
user decide.
