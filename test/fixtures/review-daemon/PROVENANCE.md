# review-daemon fixtures: where each specimen came from

Every file here was recovered from a real call on 2026-09-10 and frozen, as
`references/specimen-recovery.md` requires. None is written from memory.
Each one is projected down to the fields `bin/jjstack-review-daemon` reads.
The projection keeps private-repo titles, PR bodies, and account ids out of
this public repo. The daemon reads raw API objects, so the field paths are the
real ones.

`GH` below is `GH_CONFIG_DIR=/home/jesper/.config/gh-ai-assistant-2026 gh`. That
is the reviewer identity, `ai-assistant-2026`.

| File | Recovered with |
|---|---|
| `notifications-200.txt` | `GH api -i "notifications?per_page=100" --jq '[.[] \| {id, unread, reason, updated_at, subject: {type: .subject.type, url: .subject.url, title: (if .repository.private then "<private>" else .subject.title end)}, repository: {full_name: .repository.full_name, private: .repository.private, owner: {login: .repository.owner.login}}}]'` |
| `notifications-304.txt` | `GH api -i -H "If-Modified-Since: Thu, 10 Sep 2026 16:08:34 GMT" "notifications?per_page=100"`, stdout. gh exited 1 on the 304 |
| `notifications-304.err` | the same call, stderr: `gh: HTTP 304` |
| `search.json` | `GH api -X GET search/issues -f q="is:pr repo:disciplin-run-org/jjstack" -f per_page=2 --jq '{total_count, incomplete_results, items: [.items[] \| {number, repository_url, html_url, state, draft, pull_request: {url: .pull_request.url}}]}'` |
| `search-empty.json` | `GH api -X GET search/issues -f q="is:pr is:open review-requested:ai-assistant-2026" -f per_page=100 --jq '{total_count, incomplete_results, items}'` |
| `pull-open.json` | `GH api repos/JesperJurcenoks/inboundsavvy-cms/pulls/584 --jq '{number, state, merged, draft, merged_at, closed_at, updated_at, html_url, head: {sha: .head.sha}}'` |
| `pull-merged.json` | the same projection on `repos/disciplin-run-org/jjstack/pulls/48` |
| `pull-closed.json` | the same projection on `repos/disciplin-run-org/jjstack/pulls/33`, closed unmerged |
| `reviews.json` | `GH api "repos/disciplin-run-org/jjstack/pulls/48/reviews?per_page=100" --jq '[.[] \| {id, user: {login: .user.login}, state, submitted_at, commit_id}]'` |
| `pull-cleared.json` | `GH api repos/disciplin-run-org/jjstack/pulls/49 --jq '{number, state, merged, draft, merged_at, closed_at, created_at, updated_at, html_url, user: {login: .user.login}, head: {sha: .head.sha, repo: {full_name: .head.repo.full_name}}, requested_reviewers: [.requested_reviewers[] \| {login}]}'`, taken after the reviewer posted, when GitHub had cleared its request |
| `pull-pending.json` | derived, not fetched: `pull-cleared.json` with `requested_reviewers` set to the `requested_reviewer` of the last `review_requested` event in `events.json`. No open PR anywhere had a pending request at freeze time |
| `events.json` | `GH api "repos/disciplin-run-org/jjstack/issues/49/events?per_page=100" --jq '[.[] \| {event, created_at, actor: {login: .actor.login}, requested_reviewer: (if .requested_reviewer then {login: .requested_reviewer.login} else null end)}]'` |
| `events-paginated.txt` | `GH api --paginate "repos/disciplin-run-org/jjstack/issues/48/events?per_page=2"`, raw. gh 2.4.0 prints one JSON array per page, back to back, with nothing between them |
| `workers.json` | `GET http://localhost:8001/api/workers` with the hub bearer. Rows are filtered to `Code-Review-*` and cut to `name, online, state, last_activity, exited_cleanly` |
| `transcript-mixed.jsonl` | every `type == "assistant"` line of the Code-Review session `176a7e3e-e8a6-43d1-b03b-7fc0fa2c141d.jsonl`, cut to `type, isSidechain, timestamp, message.model`. It holds 77 `claude-fable-5-1` lines, then 210 `claude-opus-5` lines |
| `transcript-fable-last.jsonl` | `transcript-mixed.jsonl` cut after its last main-chain line that is not Opus |
| `transcript-synthetic.jsonl` | the last two real assistant lines before, and the one `<synthetic>` line in, the Code-Review session `ed089859-4604-4749-9128-ae84832f5212.jsonl`, cut to the same four fields. Claude Code writes `<synthetic>` as a placeholder, not a model |
| `transcript-boot.jsonl` | the Code-Review session `858fd049-4dba-4ef2-8de1-e18c28115e26.jsonl` before its first turn, cut to record types. It is what a freshly started worker writes: no assistant line and no model yet |

Two facts these specimens pin down:

- **gh 2.4.0 exits 1 on a 304, but still prints the `-i` headers on stdout.**
  So the daemon reads the status line and ignores the exit code.
  `notifications-304.txt` and `.err` are that exact output.
- **The hub roster lists a `<worker>-manager` row beside every worker.** So the
  daemon matches a worker by its exact name, never by prefix.
