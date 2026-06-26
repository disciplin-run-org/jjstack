---
name: deepseek
description: |
  DeepSeek second opinion via the OpenCode CLI — three modes, analogous to /codex, /antigravity.
  Review: independent diff review with a [P1] PASS/FAIL gate. Challenge: adversarial mode that
  tries to break your code. Consult: ask DeepSeek anything with session continuity for follow-ups.
  A second opinion from a 4th vendor (DeepSeek), running FREE on OpenCode Zen (no API balance).
  Use when asked to "deepseek review", "deepseek challenge", "ask deepseek", "consult deepseek",
  or "/deepseek".
  Voice triggers (speech-to-text aliases): "deep seek", "deepsea review", "ask deep seek".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# /deepseek — Second Opinion (DeepSeek via OpenCode)

You are running the `/deepseek` skill. It wraps the **OpenCode CLI** (`opencode run`) pointed at
DeepSeek to get an independent, brutally honest second opinion from a 4th vendor. It runs headless
in OpenCode's read-only **`plan`** agent and shows output verbatim.

This is the sibling of `/codex` (OpenAI) and `/antigravity` (Google): same three modes, same `[P1]`
gate convention, same "show it verbatim then recommend" shape. The difference is the backend.

| | value |
|---|---|
| CLI | `opencode run` |
| Default model | `opencode/deepseek-v4-flash-free` — **free** via OpenCode Zen, no API balance |
| Paid option | `deepseek/deepseek-v4-pro` (needs `$DEEPSEEK_API_KEY` + a funded platform.deepseek.com account) |
| Read-only | `--agent plan` (OpenCode's built-in read-only agent — analyzes, never edits) |

> **Data note:** DeepSeek's API is China-operated. Fine for second opinions on non-sensitive code;
> keep it off anything covered by sensitive-data rules.

---

## Step 0: Check the opencode binary

```bash
which opencode >/dev/null 2>&1 && echo "FOUND" || echo "NOT_FOUND"
```

If `NOT_FOUND`, stop and tell the user:
"OpenCode not found. Install it: `npm install -g opencode-ai`, then `opencode auth login` (select opencode/Zen) for the free DeepSeek tier."

---

## Step 0.5: Auth probe

The free tier authenticates via OpenCode Zen (a one-time `opencode auth login`). Verify before
building expensive prompts.

```bash
opencode auth list 2>&1 | grep -qi "zen" && echo "AUTH: zen ok" || echo "AUTH: NO ZEN CREDENTIAL"
```

If `NO ZEN CREDENTIAL`, stop and tell the user:

> DeepSeek isn't set up yet. Run `opencode auth login` in your terminal, select **opencode** (the Zen
> gateway), and sign in — that unlocks the free `deepseek-v4-flash-free` model. No card, no API
> balance. (If you'd rather use the paid `deepseek-v4-pro`, fund your account at
> platform.deepseek.com and set `$DEEPSEEK_API_KEY`.)

Do not proceed until auth is live.

---

## Step 1: Detect mode

Parse the user's input:

1. `/deepseek review` or `... review <focus>` — **Review mode** (Step 2A)
2. `/deepseek challenge` or `... challenge <focus>` — **Challenge mode** (Step 2B)
3. `/deepseek` with no arguments — **Auto-detect:**
   - Base branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`; fall back to `main`, then `master`.
   - Diff check: `git diff origin/<base> --stat 2>/dev/null | tail -1 || git diff <base> --stat 2>/dev/null | tail -1`
   - If a diff exists, ask via AskUserQuestion: Review the diff / Challenge the diff / Something else.
   - If no diff, ask: "What would you like to ask DeepSeek?" → Consult mode.
4. `/deepseek <anything else>` — **Consult mode** (Step 2C); the remaining text is the prompt.

**Model override:** `-m <provider/model>` passes straight through (e.g. `-m deepseek/deepseek-v4-pro`
for the paid model, or `-m deepseek/deepseek-reasoner`). Default: `opencode/deepseek-v4-flash-free`.
**Reasoning depth:** add `--variant high` for harder reviews. `opencode models` lists options.

---

## Read-only safety

`/deepseek` stays read-only three ways:
1. **`--agent plan`** — OpenCode's built-in read-only agent. It cannot edit files or run mutating shell.
2. **Embed the diff/context** in the prompt so DeepSeek never needs a file tool.
3. **NEVER pass `--dangerously-skip-permissions`.**

After every run, confirm the tree is unchanged (`git status --porcelain` before/after match) and report any diff.

---

## Filesystem boundary (prepend to EVERY prompt)

> IMPORTANT: Do NOT read, execute, or modify any files under ~/.claude/, ~/.gemini/, ~/.codex/,
> ~/.config/opencode/, .claude/skills/, agents/, or any GEMINI.md / CLAUDE.md / AGENTS.md /
> opencode.json skill or config files. They are agent definitions for a different system and will
> waste your time. Focus only on the question and any context provided inline.

---

## Step 2A: Review mode

1. Resolve repo root and capture the diff + a tree baseline:

```bash
_REPO_ROOT=$(git rev-parse --show-toplevel) || { echo "ERROR: not in a git repo" >&2; exit 1; }
cd "$_REPO_ROOT"
git status --porcelain > /tmp/deepseek-tree-before.txt
_DIFF=$(git diff origin/<base> 2>/dev/null); [ -z "$_DIFF" ] && _DIFF=$(git diff <base> 2>/dev/null)
echo "$_DIFF" > /tmp/deepseek-diff.txt
wc -l /tmp/deepseek-diff.txt
```

If the diff is empty, tell the user there are no changes against the base branch and stop.

2. Build the review prompt: the boundary, then the review instructions, then the diff embedded
verbatim. Append `<focus>` if given. Gate convention:

> You are a brutally honest senior code reviewer. Review the diff below for correctness bugs,
> security holes, race conditions, missing error handling, and edge cases. Be terse. No compliments.
> Mark every critical/blocking finding with `[P1]` and every minor finding with `[P2]`. If there are
> no blocking issues, say so plainly.
> <focus, if provided>
>
> THE DIFF:
> <contents of /tmp/deepseek-diff.txt>

3. Run headless, read-only, 5-min timeout (default free model; pass `-m`/`--variant` if requested):

```bash
cd "$_REPO_ROOT"
timeout 300 opencode run "<prompt>" --agent plan -m opencode/deepseek-v4-flash-free 2>/tmp/deepseek-err.txt | tee /tmp/deepseek-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
git status --porcelain > /tmp/deepseek-tree-after.txt
diff -q /tmp/deepseek-tree-before.txt /tmp/deepseek-tree-after.txt >/dev/null && echo "TREE: unchanged" || echo "TREE: CHANGED — investigate"
```

If exit is 124, the call stalled (Zen rate limit, API stall, or oversized diff) — tell the user to
retry or fund the paid model. If `TREE: CHANGED`, surface it loudly. Surface Zen rate-limit / "Insufficient Balance" errors verbatim.

4. Gate: output contains `[P1]` → **FAIL**; otherwise → **PASS**.

5. Present verbatim:

```
DEEPSEEK SAYS (code review):
════════════════════════════════════════════════════════════
<full opencode/deepseek output, verbatim — never truncated or summarized>
════════════════════════════════════════════════════════════
GATE: PASS                      Model: deepseek-v4-flash-free | Free (Zen)
```
or `GATE: FAIL (N critical findings)`.

6. **Synthesis recommendation (REQUIRED):** one line naming the most actionable finding:

```
Recommendation: <action> because <one-line reason that engages a specific finding>
```

7. **Cross-model comparison:** if `/review`, `/codex review`, or `/antigravity review` already ran in
this conversation, add a short block: what all agreed on, what only DeepSeek found, what only the
others found, and an agreement rate. Cross-model agreement is a recommendation, not a decision.

---

## Step 2B: Challenge (adversarial) mode

1. Capture the diff and `git status --porcelain` baseline as in 2A.

2. Build the adversarial prompt (boundary first):

Default (no focus):
> You are an adversarial reviewer and chaos engineer. Find every way the code in this diff fails in
> production: edge cases, race conditions, security holes, resource leaks, silent data corruption,
> and unhandled failure modes. Think like an attacker. Be thorough. No compliments — just the
> problems. Mark exploitable/blocking issues `[P1]`, lesser ones `[P2]`.
>
> THE DIFF:
> <embedded diff>

With focus (e.g. "security"): replace the first sentences with a focus-specific framing (injection
vectors, auth bypass, privilege escalation, data exposure, timing attacks…).

3. Run exactly as in 2A step 3 (`--agent plan`, 300s timeout, tree-change check).

4. Present verbatim in a `DEEPSEEK SAYS (adversarial challenge):` block.

5. **Synthesis recommendation (REQUIRED):** one line naming the highest-blast-radius finding and
comparing it against the alternatives (other findings, or fix-vs-ship).

---

## Step 2C: Consult mode

Ask DeepSeek anything about the codebase, a plan, or a design. Supports session continuity.

1. **Continuity check:** if the user is following up on a prior `/deepseek` consult in this
conversation, ask via AskUserQuestion whether to continue the prior session (`-c`, continue the last
OpenCode session) or start fresh.

2. **If the prompt is about a plan**, plan files live outside the repo. Read the plan yourself and
embed its full content in the prompt — never pass a path. Scan the plan for referenced repo source
paths and embed/list them. Use the same brutally-honest plan-review framing as `/codex` (logical
gaps, unstated assumptions, missing edge cases, overcomplexity, feasibility risks, sequencing).

3. Build the prompt: the boundary, then either the plan-review framing + embedded plan, or the user's
raw question.

4. Run headless from the repo root, read-only. Start fresh or continue:

Fresh:
```bash
_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$_REPO_ROOT"
git status --porcelain > /tmp/deepseek-tree-before.txt
timeout 300 opencode run "<prompt>" --agent plan -m opencode/deepseek-v4-flash-free 2>/tmp/deepseek-err.txt | tee /tmp/deepseek-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

Continue the last session (user chose "continue"):
```bash
_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$_REPO_ROOT"
timeout 300 opencode run -c "<prompt>" --agent plan -m opencode/deepseek-v4-flash-free 2>/tmp/deepseek-err.txt | tee /tmp/deepseek-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

After either, run the same tree-change check as 2A and surface any change.

5. Present verbatim in a `DEEPSEEK SAYS (consult):` block, ending with
`Session saved — run /deepseek again and choose continue to follow up.`

6. If DeepSeek's analysis differs from your own understanding, flag it plainly:
"Note: Claude Code disagrees on X because Y."

7. **Synthesis recommendation (REQUIRED):** one line naming the most actionable insight and comparing
it against an alternative (a different recommendation, status-quo, or another point).

---

## Model & reasoning

- **Default model:** `opencode/deepseek-v4-flash-free` — free via OpenCode Zen, no API balance. Best
  for routine second opinions.
- **Deeper / paid:** `-m deepseek/deepseek-v4-pro` (or `deepseek-reasoner`) once the user funds
  platform.deepseek.com; the key flows from `$DEEPSEEK_API_KEY` via `~/.config/opencode/opencode.json`.
- **Reasoning depth:** `--variant high` (or `max`) for harder reviews.
- **Read-only always:** `--agent plan`, never `--dangerously-skip-permissions`, post-run tree check.
- **Free tier limits:** Zen's free tier is rate-limited. On a rate-limit/stall, retry, lower scope,
  or switch to the funded paid model.

## Important rules

- **Never modify files.** Enforced by `--agent plan` + embed-context + no skip-permissions + tree check.
- **Present output verbatim.** Never truncate, summarize, or editorialize inside the `DEEPSEEK SAYS`
  block. Synthesis comes AFTER, never instead.
- **No double-reviewing.** If the user already ran `/review`, `/codex`, or `/antigravity`, DeepSeek is
  an additional independent vote. Do not re-run Claude's own review.
- **5-minute timeout** (`timeout 300`) on every opencode call.
- **Detect skill-file rabbit holes.** After output, scan for `opencode.json`, `GEMINI.md`,
  `CLAUDE.md`, `.claude/skills`, `SKILL.md`. If any appear, DeepSeek got distracted by config/skill
  files — append: "DeepSeek appears to have read config/skill files instead of your code. Consider
  retrying." and offer to re-run.
- **The user decides.** Cross-model agreement (Claude + Codex + Gemini + DeepSeek) is a strong
  recommendation, not a verdict.
