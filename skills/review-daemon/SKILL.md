---
name: review-daemon
description: >
  Start, check, or stop the review daemon, a foreground poller that opens one
  Claude Code review session per pull request for the reviewer account
  ai-assistant-2026. For each review request (an @-mention starts nothing),
  it spawns a worker
  in ~/PycharmProjects/Code-Review, confirms the session runs on Opus, sends
  it /review, sends later rounds to the same session, and ends it with
  /save-and-exit when the PR merges or closes. Only repos owned by
  JesperJurcenoks or disciplin-run-org are served; other requests are logged
  and ignored.
  Use when the user says "start the review daemon", "is the review daemon
  running", "which PRs are being reviewed", "review queue", "why did my PR
  not get a review", "stop the review daemon", or invokes /review-daemon.
  Do NOT use to review a PR yourself (use /review), to answer review findings
  (use /receiving-code-review), or to end one review session by hand (type
  /save-and-exit in that session).
allowed-tools:
  - Bash
  - Read
---

# review-daemon: one review session per pull request, opened for you

The daemon does the reviewer side of rung 4 so a person does not have to. A
request for `ai-assistant-2026` becomes a worker session named after the PR.
That session runs `/review` and stays open for the rounds after fixes. It
closes itself with `/save-and-exit` when the PR is done. This skill is how you
start the daemon, see what it is doing, and stop it. The daemon is the program
`bin/jjstack-review-daemon`, and the contract it keeps is one file:

```bash
cat ~/.claude/skills/jjstack/references/review-daemon.md
```

Read that before answering anything about what the daemon will or will not do.

## When to use

- "start the review daemon" / "start reviewing PRs automatically"
- "is the review daemon running?" / "which PRs are being reviewed?"
- "why did my PR not get a review?"
- "stop the review daemon"

## The process

### Start it

The daemon runs in the foreground, forever, so it belongs in a terminal of its
own. Never run it through this session's Bash tool. That call would block until
it timed out, and the timed-out process would keep running unseen. Give the
user the command to run in a new terminal:

```bash
cd ~/PycharmProjects/Code-Review
jjstack-review-daemon
```

If `jjstack-review-daemon` is not on PATH, the full path is
`~/.claude/skills/jjstack/bin/jjstack-review-daemon`, and re-running jjstack's
`setup` links it into `~/.local/bin`.

To show what one poll would do without changing anything, run this. It is
safe to run from this session:

```bash
jjstack-review-daemon --cwd ~/PycharmProjects/Code-Review --once --dry-run
```

It exits 3 if the GitHub identity is wrong. Say which of the three reasons it
printed: a token in the environment, no `GH_CONFIG_DIR`, or a login other than
`ai-assistant-2026`.

### Check on it

- What it tracks: `jjstack-review-daemon --cwd ~/PycharmProjects/Code-Review --status`
- Whether it is alive: the last lines of
  `~/PycharmProjects/Code-Review/.review-daemon/daemon.log` carry one line per
  poll. A newest line older than a few minutes means it is not running.
- The sessions: `tm_list_workers` shows each `Code-Review-<repo>-pr<N>-tm`,
  and `tm_screenshot` of one shows where its round is.
- Why a PR got nothing: look it up in `history.jsonl` (ended), in
  `ignored.jsonl` (the owner is off the allowlist, or the request was made by
  someone without write access), in `daemon.log` (a thread update that was
  not a new request), and in the console lines. The usual causes are a PR
  that was already closed, a missing re-request after fixes, an @-mention
  where a review request was needed, a re-request by the PR's author rather
  than a writer, or the queue being full at four sessions.

### Stop it

Ctrl-C in its terminal. Open sessions keep running and the ledger is saved.
The next start picks them up. To end one session early, type `/save-and-exit`
in its window.

## Interaction with other skills

- `/review` is what each session runs. The daemon only decides when to send
  it, and to which session.
- `/save-and-exit` is how each session ends. The daemon sends it and never
  kills a session.
- `/receiving-code-review` is the author's half. Its re-request after a fix is
  what starts the next round in the same session.

## Anti-patterns

- Running the daemon inside a Claude session's Bash tool.
- Ending a review session with `tm_stop` or by closing its window mid-round.
  A killed session loses the ending sweep. The daemon also reads it as a
  crash and resumes it.
- Adding an owner to `--owners` to review a stranger's repo. The allowlist is
  what stops the reviewer being used for free.
- Starting a second daemon on the same directory. Both would share one
  ledger and open duplicate sessions.
