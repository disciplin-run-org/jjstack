# The review daemon: one review session per pull request, opened for you

`bin/jjstack-review-daemon` automates the reviewer side of rung 4. It watches
GitHub as `ai-assistant-2026`. For every review request, or @-mention by someone
with write access, on a pull request it opens a Claude Code worker session in `~/PycharmProjects/Code-Review`
and sends that session `/review <owner>/<repo> pr <N>`. The session stays open
for later rounds and ends with `/save-and-exit` once the PR is merged or
closed. Before the daemon, a person did each of those steps by hand. This file
is the contract: what the daemon does, in what order, and what it never does.
`references/independent-review.md` says why the reviewer is a separate session.
This file says how that session is started and stopped.

## Running it

It is a foreground process. Start it by hand, in its own terminal, from the
reviewer directory:

```bash
cd ~/PycharmProjects/Code-Review
jjstack-review-daemon
```

`--cwd ~/PycharmProjects/Code-Review` does the same from anywhere else.
`--once --dry-run` prints what one poll would do and changes nothing.
`--status` lists the PRs in the ledger. Ctrl-C stops the daemon and leaves
every open session running; the next start picks them up from the ledger.
`--help` lists every option.

Do not run it from inside a Claude session's Bash tool. It never returns, so
the call blocks until it times out, and a timed-out call keeps running in the
background.

## What starts a session

- **Sources.** The primary source is GitHub notifications for the reviewer,
  `GET /notifications`, polled with `If-Modified-Since`. A quiet poll costs a
  304 with no body. On the first poll, and every `--reconcile-every` polls
  after it (default 15), one search also catches requests the feed missed:
  `is:pr is:open review-requested:ai-assistant-2026`.
- **Reasons.** Only a notification with reason `review_requested` or `mention`
  on a `PullRequest` counts. Comment, subscription and Issue notifications are
  left alone and stay unread.
- **A thread update is not a request.** GitHub moves a thread's update time on
  a merge and on a comment too, and the reason stays the same. So before it
  acts, the daemon confirms the request behind the notification:
  - A review request on a PR with no session counts only while GitHub still
    lists `ai-assistant-2026` in the PR's `requested_reviewers`.
  - A review request on a PR that has a session counts only if the PR's
    events hold a `review_requested` event for the reviewer that is newer
    than the last round.
  - A mention counts only if a comment, a review, or the PR description,
    written after the last round, mentions `@ai-assistant-2026` and was
    written by someone with write or admin access to the repo. GitHub
    already puts that gate on a review request. Anyone can mention an
    account on a public repo, but only a writer can request its review.
    Without the gate, a stranger's mention would open a session that runs
    the PR's own tooling. A permission lookup that fails counts as no
    access. The mention's text is not passed on.

  An update that confirms nothing is marked read and written to `daemon.log`.
  A mention from someone without write access also goes to `ignored.jsonl`.
- **Owners.** Only repos whose owner is on `--owners` are served. The default
  list is `JesperJurcenoks,disciplin-run-org`, compared without case. A
  request from anyone else is written to `ignored.jsonl` and nowhere else.
  It gets no console line, no reply on GitHub, no session, and it stays
  unread. That keeps a stranger who adds the reviewer to their repo from
  getting free reviews.
- **Drafts.** A draft is reviewed if someone requested it.
- **Closed PRs.** A request on a PR that is already merged or closed is
  skipped. The daemon says so once and marks the thread read.
- **Once per update.** Each notification the daemon handles is marked read on
  GitHub. It is also recorded in the ledger by thread id and update time, so
  the same update is never handled twice. A newer update is checked again as
  described above; the newer time alone proves nothing.

## The session

- **Name.** The role is `<repo>-pr<N>` and the worker is
  `<cwd basename>-<repo>-pr<N>-tm`, for example
  `Code-Review-jjstack-pr12-tm`. The hub refuses a worker name over 64
  characters or with a `#`, so the daemon refuses to make one.
- **Spawn.** A new gnome-terminal window, titled with the worker name,
  working in the reviewer directory, runs:

  ```bash
  claude-tm --role=<repo>-pr<N> --model opus[1m] --session-id <uuid>
  ```

  The daemon picks the uuid and keeps it, so it can resume that exact session
  later. `claude-tm` loads the directory's `.env`, which gives the session the
  reviewer's `gh` identity. `--dangerously-skip-permissions` comes from
  `TM_DANGEROUSLY_SKIP_PERMISSIONS` in `~/.config/tubemail/.env`, as for every
  worker on this machine.
- **Handshake.** A freshly started worker writes no model line until it takes
  a turn. And the hub reports `idle` before Claude has finished starting. So
  once the worker is online and idle, the daemon sends it one line asking it
  to reply `READY`. That reply is the readiness check.
- **Model gate.** The daemon reads the session transcript,
  `~/.claude/projects/<dashed cwd>/<uuid>.jsonl`, and takes the newest
  main-chain assistant line written after the handshake. Subagent lines and
  `<synthetic>` placeholders are skipped. The model must start with
  `claude-opus`. If it does not, the review is not sent. The daemon sends
  `/exit`, then opens a fresh session once with `--retry-model` (default
  `claude-opus-5[1m]`). If that session is also not on Opus, the daemon
  prints an error and leaves the PR for a person. The model is checked again
  before every round, not only the first.
- **Dispatch.** Once the model passes and the worker is idle, the daemon sends
  `/review <owner>/<repo> pr <N>`. It never sends to a worker that is not
  online, because a message to an unknown name creates a ghost row on the hub.
- **Next rounds.** A re-request, or a new mention by someone with write
  access, on the same PR goes to the same worker, so the round knows what the last one found. If the worker is
  busy, the daemon waits for idle. It never interrupts.
- **Long rounds.** A round over an hour is normal. The daemon prints one note
  an hour and does nothing else.
- **Sessions started by hand.** If a worker with the PR's name is already
  online, the daemon uses it instead of opening a second one. It finds that
  session's transcript by its `agent-name` line.

## When a session stops

- **Crash.** The worker is off the hub, did not exit cleanly, and its
  `claude-tm` pid is dead. The daemon reopens it with `--resume <uuid>`. If a
  round was running and no review was posted since, the round is sent again.
- **Clean exit while the PR is open.** Someone typed `/exit`. The session stays
  closed until the next request, which resumes it.
- **Running but not on the hub.** The pid is alive but the hub cannot see it.
  The daemon warns once an hour and leaves it alone. It never starts a second
  process for the same name.
- **Slow start.** For five minutes after a spawn the daemon waits and does not
  judge. After three failed starts it stops and says the PR needs a person.

## Ending a session

A session ends when its PR is merged, when it is closed unmerged, or when
`--idle-days` pass (default 7) with no request, no round, no review, and no
update on the PR. The daemon waits until the worker is idle and sends it
`/save-and-exit`. That skill keeps the session's lessons and exits through the
harness's own path. When the hub shows the worker offline with a clean exit,
the record moves to `history.jsonl`. If the worker is still open 15 minutes
later, the daemon sends `/save-and-exit` once more, and never a third time.
A request that arrives for a PR whose session is ending is ignored, and the
daemon says why.

## Limits

- **Concurrency.** At most `--max-sessions` sessions run at once (default 4).
  Later requests wait in first-come order, and each one starts when a session
  ends. A queued PR that closes before its turn is dropped without a session.
- **Hub down.** The daemon warns once and changes no session until the hub
  answers again. It keeps reading GitHub, so no request is lost.

## State and logs

Everything lives in `<cwd>/.review-daemon/`:

| File | What it holds |
|---|---|
| `ledger.json` | One record per tracked PR: worker, session uuid, status (`queued`, `active`, `ending`), the last round, the last review, the end reason. It also holds the handled threads and the feed's `Last-Modified`. Writes are atomic. |
| `history.jsonl` | Each ended record, appended once. |
| `ignored.jsonl` | Requests from owners off the allowlist, one line per request. |
| `daemon.log` | One line per poll, including the quiet ones, so you can tell the daemon is alive without watching its console. |

The console prints only what happened, never an empty poll. Warnings are
yellow, errors bright magenta, and notes bright cyan. It never prints red.

## Identity

The daemon refuses to start, with exit 3, if `GH_TOKEN` or `GITHUB_TOKEN` is
set. Either one overrides `GH_CONFIG_DIR`, so reviews would post as whoever
owns that token. It also refuses when `GH_CONFIG_DIR` is unset after reading
`<cwd>/.env`, and when `gh api user` is not `ai-assistant-2026`. A review
posted as the PR's author cannot approve it, so rung 4 could never be met.

## GitHub quirks it depends on

- On a 304, gh 2.4.0 exits 1 but still prints the `-i` headers. The daemon
  reads the status line and ignores the exit code.
- On gh 2.4.0, `gh api search/issues -f q=...` sends a POST and gets a 404
  unless it is given `-X GET`.
- `review-requested:` lists only requests still pending. A request clears as
  soon as the reviewer posts any review. So the sweep finds only real
  backlog, and a round after fixes needs the author's re-request.
- A merge moves a `review_requested` thread's update time and marks it
  unread again, with the reason unchanged. This was measured on five threads.
  A comment does the same for a subscribed reviewer.
- On gh 2.4.0, `--paginate` prints one JSON array per page, back to back, with
  nothing between them. The daemon reads that as a stream of arrays.
- The permission endpoint answers `read`, not 404, for an account with no
  access to a public repo.
- The notification feed carries `X-Poll-Interval: 60`. The daemon never polls
  faster than that. Two minutes costs about 30 core calls an hour, plus two
  per open session.

## What it never does

- It never kills a session. It does not call `tm_stop`, send a signal, or
  close a window. Every ending goes through `/save-and-exit` inside the
  session.
- It never posts on GitHub. It only marks threads read. The review is the
  session's work.
- It never serves an owner off the allowlist, and never acts on a mention from
  someone without write access.
- It never sends a round to a session whose model it has not checked.

The frozen specimens behind these rules are in
`test/fixtures/review-daemon/`, with their recovery commands in
`PROVENANCE.md`. The unit suite is `test/review-daemon-check.py`.
