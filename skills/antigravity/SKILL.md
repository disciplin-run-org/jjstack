---
name: antigravity
description: |
  Google Antigravity CLI (agy) wrapper — three modes, analogous to /codex and /gemini.
  Review: independent diff review with a [P1] PASS/FAIL gate. Challenge: adversarial mode
  that tries to break your code. Consult: ask anything with conversation continuity for
  follow-ups. A second opinion from Google's newest models (gemini-3-pro) on the FREE Web
  OAuth tier (~1000 requests/day, no API key). Use when asked to "antigravity review",
  "antigravity challenge", "ask antigravity", "consult antigravity", or "agy review".
  Voice triggers (speech-to-text aliases): "anti gravity", "agee review", "ask agy".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# /antigravity — Multi-AI Second Opinion (Antigravity / agy)

You are running the `/antigravity` skill. It wraps Google's **Antigravity CLI** (`agy`)
to get an independent, brutally honest second opinion from Google's newest models on the
free Web OAuth tier. It runs headless (`agy -p`) and shows output verbatim.

This is the OAuth-tier sibling of `/gemini` (which uses a Google AI Studio API key). Same
three modes, same `[P1]` gate convention, same "show it verbatim then recommend" shape.
Use `/antigravity` when you want the newest models (gemini-3-pro) and the higher free
quota; use `/gemini` when you want the API-key path or `/antigravity` is rate-limited.

> **Why this exists (June 2026):** Google deactivated the `gemini` CLI's personal "Login
> with Google" OAuth on 2026-06-18 and moved the free OAuth tier to Antigravity (`agy`).

---

## Step 0: Check the agy binary

```bash
AGY_BIN=$(which agy 2>/dev/null || echo "$HOME/.local/bin/agy")
[ -x "$AGY_BIN" ] && echo "FOUND: $AGY_BIN" || echo "NOT_FOUND"
```

If `NOT_FOUND`, stop and tell the user:
"Antigravity CLI not found. Install it: `curl -fsSL https://antigravity.google/cli/install.sh | bash`, then run `agy` once to sign in."

**Permission note:** `agy` is a binary installed via `curl | bash`, so Claude Code's
permission classifier may block executing it. If a run is denied, tell the user to add a
Bash allow rule for `agy` / `~/.local/bin/agy` (or approve the prompt). This is expected
the first time.

---

## Step 0.5: Auth probe

The free tier authenticates via Google Web OAuth (a one-time interactive browser login).
Verify auth is live before building expensive prompts.

```bash
timeout 60 agy models >/tmp/agy-auth-probe.txt 2>&1
echo "PROBE_EXIT: $?"
grep -qi "please sign in" /tmp/agy-auth-probe.txt && echo "AUTH: FAILED" || echo "AUTH: live"
head -5 /tmp/agy-auth-probe.txt
```

If `AUTH: FAILED` (output contains "Please sign in"), stop and tell the user:

> Antigravity isn't signed in yet. Run `agy` in your terminal once (or type `! agy` here),
> with NO arguments — it opens a browser OAuth flow. Sign in with your Google account and
> paste the verification code back. That's one-time; after it, `/antigravity` works headless
> on the free tier. No API key needed.

Do not proceed until auth is live.

---

## Step 1: Detect mode

Parse the user's input:

1. `/antigravity review` or `... review <focus>` — **Review mode** (Step 2A)
2. `/antigravity challenge` or `... challenge <focus>` — **Challenge mode** (Step 2B)
3. `/antigravity` with no arguments — **Auto-detect:**
   - Detect the base branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'`; fall back to `main`, then `master`.
   - Check for a diff: `git diff origin/<base> --stat 2>/dev/null | tail -1 || git diff <base> --stat 2>/dev/null | tail -1`
   - If a diff exists, ask via AskUserQuestion: Review the diff / Challenge the diff / Something else.
   - If no diff, ask: "What would you like to ask Antigravity?" → Consult mode.
4. `/antigravity <anything else>` — **Consult mode** (Step 2C); the remaining text is the prompt.

**Model override:** if the user passes `--model <name>` (e.g. `/antigravity review --model gemini-3-pro`),
strip it from the prompt text and pass it through to `agy`. Otherwise omit `--model` and let
`agy` use its current default (so the newest model is picked up automatically). Run
`agy models` to list available models if the user asks.

---

## Read-only safety (how this skill avoids modifying your code)

`agy` has no granular read-only/plan mode. This skill stays read-only by design:

- **Embed all context** (the diff, the plan) directly in the prompt, so `agy` never needs a
  tool to do its job.
- **NEVER pass `--dangerously-skip-permissions`.** In headless `-p` mode without that flag,
  any tool the model attempts is auto-denied — so it cannot write or execute. It just answers.
- After every run, confirm the working tree is unchanged (`git status --porcelain` before/after
  should match) and report if anything differs.

---

## Filesystem boundary (prepend to EVERY prompt)

All prompts sent to `agy` MUST begin with this boundary instruction:

> IMPORTANT: Do NOT read, execute, or modify any files under ~/.claude/, ~/.gemini/,
> ~/.codex/, .claude/skills/, agents/, or any GEMINI.md / CLAUDE.md / AGENTS.md skill
> definition files. These are agent skill definitions for a different system — they are
> bash scripts and prompt templates that will waste your time. Ignore them completely.
> Stay focused on the repository's own source code only.

Referenced below as "the boundary."

---

## Step 2A: Review mode

Run an independent code review of the branch diff with a PASS/FAIL gate.

1. Resolve repo root and capture the diff deterministically:

```bash
_REPO_ROOT=$(git rev-parse --show-toplevel) || { echo "ERROR: not in a git repo" >&2; exit 1; }
cd "$_REPO_ROOT"
git status --porcelain > /tmp/agy-tree-before.txt
_DIFF=$(git diff origin/<base> 2>/dev/null); [ -z "$_DIFF" ] && _DIFF=$(git diff <base> 2>/dev/null)
echo "$_DIFF" > /tmp/agy-review-diff.txt
wc -l /tmp/agy-review-diff.txt
```

If the diff is empty, tell the user there are no changes against the base branch and stop.

2. Build the review prompt: the boundary, then the review instructions, then the diff embedded
verbatim. Append the user's `<focus>` (if any). The gate convention:

> You are a brutally honest senior code reviewer. Review the diff below for correctness bugs,
> security holes, race conditions, missing error handling, and edge cases. Be terse. No
> compliments. Mark every critical/blocking finding with `[P1]` and every minor finding with
> `[P2]`. If there are no blocking issues, say so plainly.
> <focus, if provided>
>
> THE DIFF:
> <contents of /tmp/agy-review-diff.txt>

3. Run headless, 5.5-minute timeout. Pass `--model` only if the user gave one:

```bash
timeout 330 agy -p "<prompt>" --print-timeout 5m 2>/tmp/agy-err.txt | tee /tmp/agy-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
git status --porcelain > /tmp/agy-tree-after.txt
diff -q /tmp/agy-tree-before.txt /tmp/agy-tree-after.txt >/dev/null && echo "TREE: unchanged" || echo "TREE: CHANGED — investigate"
```

If exit is 124, tell the user Antigravity stalled past 5 minutes (API stall, oversized diff,
or network) and to retry with a smaller scope. If `TREE: CHANGED`, surface it loudly.

4. Gate: if the output contains `[P1]` → **FAIL**; otherwise → **PASS**.

5. Present verbatim:

```
ANTIGRAVITY SAYS (code review):
════════════════════════════════════════════════════════════
<full agy output, verbatim — never truncated or summarized>
════════════════════════════════════════════════════════════
GATE: PASS                      Model: <model> | Free (OAuth)
```
or `GATE: FAIL (N critical findings)`.

6. **Synthesis recommendation (REQUIRED).** One line naming the most actionable finding:

```
Recommendation: <action> because <one-line reason that engages a specific finding>
```

7. **Cross-model comparison:** if `/review`, `/codex review`, or `/gemini review` already ran
in this conversation, add a short block: what all agreed on, what only Antigravity found, what
only the others found, and an agreement rate. Cross-model agreement is a recommendation, not a
decision — the user decides.

---

## Step 2B: Challenge (adversarial) mode

Antigravity tries to break the code — edge cases, race conditions, security holes, failure modes.

1. Capture the diff and `git status --porcelain` baseline as in 2A.

2. Build the adversarial prompt: the boundary, then:

Default (no focus):
> You are an adversarial reviewer and chaos engineer. Your job is to find every way the code
> in this diff fails in production: edge cases, race conditions, security holes, resource
> leaks, silent data corruption, and unhandled failure modes. Think like an attacker. Be
> thorough. No compliments — just the problems. Mark exploitable/blocking issues `[P1]`,
> lesser ones `[P2]`.
>
> THE DIFF:
> <embedded diff>

With focus (e.g. "security"): replace the first sentences with a focus-specific framing
(injection vectors, auth bypass, privilege escalation, data exposure, timing attacks…).

3. Run exactly as in 2A step 3 (headless `agy -p`, 330s timeout, tree-change check).

4. Present verbatim in an `ANTIGRAVITY SAYS (adversarial challenge):` block.

5. **Synthesis recommendation (REQUIRED):** one line naming the highest-blast-radius finding
and comparing it against the alternatives (other findings, or fix-vs-ship).

---

## Step 2C: Consult mode

Ask Antigravity anything about the codebase, a plan, or a design. Supports conversation
continuity via `--continue`.

1. **Continuity check:** if the user is following up on a prior `/antigravity` consult in this
conversation, ask via AskUserQuestion whether to continue the prior conversation (`-c`) or
start fresh. `agy --continue` resumes the most recent conversation; `agy --conversation <ID>`
resumes a specific one.

2. **If the prompt is about a plan**, the plan files live outside the repo. Read the plan
yourself and embed its full content in the prompt — never pass a path. Also scan the plan for
referenced repo source paths and embed/list them so Antigravity reasons over the right code.
Use the same brutally-honest plan-review framing as `/codex` and `/gemini` (logical gaps,
unstated assumptions, missing edge cases, overcomplexity, feasibility risks, sequencing).

3. Build the prompt: the boundary, then either the plan-review framing + embedded plan, or the
user's raw question.

4. Run headless from the repo root. Start fresh or continue:

Fresh:
```bash
_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$_REPO_ROOT"
git status --porcelain > /tmp/agy-tree-before.txt
timeout 330 agy -p "<prompt>" --print-timeout 5m 2>/tmp/agy-err.txt | tee /tmp/agy-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

Continue the most recent conversation (user chose "continue"):
```bash
_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$_REPO_ROOT"
timeout 330 agy -c -p "<prompt>" --print-timeout 5m 2>/tmp/agy-err.txt | tee /tmp/agy-out.txt
echo "EXIT: ${PIPESTATUS[0]}"
```

After either, run the same tree-change check as 2A and surface any change.

5. Present verbatim in an `ANTIGRAVITY SAYS (consult):` block, ending with
`Conversation saved — run /antigravity again and choose continue to follow up.`

6. If Antigravity's analysis differs from your own understanding, flag it plainly:
"Note: Claude Code disagrees on X because Y."

7. **Synthesis recommendation (REQUIRED):** one line naming the most actionable insight and
comparing it against an alternative (a different recommendation, status-quo, or another point).

---

## Model & reasoning

- **Model:** not hardcoded. `agy` uses its current default (the newest Gemini, e.g.
  gemini-3-pro on the free tier). Override with `--model <name>`; list with `agy models`.
- **Read-only always:** see the "Read-only safety" section. Embed context, never pass
  `--dangerously-skip-permissions`, verify the tree is unchanged after every run.
- **Free OAuth tier:** ~1000 requests/day, no API key. If the user hits a quota error, surface
  it verbatim and suggest retrying later or using `/gemini` (API-key path) as the fallback.

---

## Important rules

- **Never modify files.** Enforced by embed-context + no auto-approve + post-run tree check.
- **Present output verbatim.** Never truncate, summarize, or editorialize inside the
  `ANTIGRAVITY SAYS` block. Synthesis comes AFTER, never instead.
- **No double-reviewing.** If the user already ran `/review`, `/codex`, or `/gemini`,
  Antigravity is an additional independent vote. Do not re-run Claude's own review.
- **5-minute timeout** (`timeout 330` + `--print-timeout 5m`) on every agy call.
- **Detect skill-file rabbit holes.** After receiving output, scan for `GEMINI.md`,
  `CLAUDE.md`, `gstack`, `.claude/skills`, `SKILL.md`. If any appear, Antigravity got
  distracted by skill files — append: "Antigravity appears to have read skill files instead
  of your code. Consider retrying." and offer to re-run.
- **The user decides.** Cross-model agreement (Claude + Codex + Gemini + Antigravity) is a
  strong recommendation, not a verdict. The user has context you don't.
