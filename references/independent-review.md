# Independent review — the protocol behind done-done rung 4

Rung 4 of `references/definition-of-done.md` says a PR is reviewed by a
session that did not write it before it is merged. This file is the
protocol both sides follow, the table of who must approve per repo class,
and the GitHub settings that turn the rule into a floor.

## Why the author does not review their own PR

Three reasons, the second of which is mechanical rather than taste:

1. **Same context, same blind spots.** The author's session holds the
   reasoning that produced the code, so its judgement passes rationalise
   what a reviewer would question. AR-3 measured this: three green rounds of
   self-review could not certify the phases they ran on.
2. **A posted self-review would once have corrupted the real review.**
   `/review`'s preamble treats the newest attribution-lined round on the
   thread as "the previous round". When that detector matched on the body
   prefix alone, a self-review posted first made the independent reviewer's
   pass a *re-review*: nothing below the blocking tier raised, only the
   author's own findings re-verified, the author's verdict the review of
   record. The detector now filters on the posting account as well
   (`select(.who == $me and ...)`), so a round posted by another account is
   invisible to the reviewer's lookup and the corruption cannot happen. This
   is why a self-check is allowed rather than refused - the mechanical
   objection was answered by a better fix than a refusal.
3. **The deterministic half is already free.** Phase 0 pre-flight and
   `verify.yml` give the author every fact a reviewer would get, at no model
   cost. What the author needs before requesting review is CI green and a
   `/verify-before-done` block, not a verdict on their own work.

## Who must approve, by repo class

| Repo class | Required before merge |
|---|---|
| **InboundSavvy**: `inboundsavvy-codebase`, `web-checks`, `workflow-automation`, `inboundsavvy-cms`, `Inboundsavvy-webmaster`, `inboundsavvy-brand-system`, `inboundsavvy.com`, `inboundsavvy-site-templates` (not `inboundsavvy-e2e`, which is one AI review) | The AI review (`lgtm - approved`) **first**, then at least one human reviewer: Andre (`andrezorzo`) or Santiago. Never Jesper. The human is requested only after the AI round is clean, so they review a converged PR, not a draft. |
| **disciplin.run org repos**, and Jesper's other repos | One AI review (`lgtm - approved`) is enough. |

The AI review is the floor in both classes; the human approval is an
additional requirement in the first. A repo that is not in the table gets
classified here before its first PR, not guessed at merge time.

## The author side

1. Push the branch, open the PR with the stated intent in the body (the
   pre-flight reads it; an empty body is a gap in the reviewer's evidence).
2. Wait for `verify.yml` to go green. A red check is the author's to fix
   before anyone else spends a minute on the diff.
3. Run `/verify-before-done`; the block goes in the session transcript.
4. Request the review. With the reviewer identity configured:

   ```bash
   gh api -X POST repos/<owner>/<repo>/pulls/<PR>/requested_reviewers --input - <<'JSON'
   {"reviewers":["ai-assistant-2026"]}
   JSON
   ```

   Not `gh pr edit --add-reviewer`: it resolves the PR through GraphQL and
   that query reads `projectCards`, retired with Projects classic, so on
   this repo the whole command fails with a deprecation error and the
   request is never made. Measured 2026-09-10. The REST route above has no
   such dependency.

   A tubemail message to the reviewer worker naming the PR number and repo
   works as the dispatch too. Either way the reviewer's `gh` must hold the
   reviewer token: without it the round posts under the author's account,
   GitHub refuses the approving state, and the PR stays blocked on rung 4.
5. On findings, run `/receiving-code-review`: triage, fix or answer each
   one on the thread, push, and **re-request**. Every push that answers
   findings gets a fresh round; the round that raised them never counts as
   the approval. Every fix passes `/review`'s equivalence gate before it is
   committed.
6. **InboundSavvy repos only:** after the AI lgtm, request Andre or
   Santiago. Never in parallel with the AI round.
7. Merge only when the newest review is an approval AND no commit is newer
   than it. Those are two conditions, and the second is the one that gets
   skipped: an approval from round 1 does not cover the commits round 1
   asked for. Branch protection enforces it where it is enabled
   (`dismiss_stale_reviews`); where it is not, the author checks it:

   ```bash
   gh pr view <PR> --repo <owner/repo> --json reviews,commits --jq '"last review: \(.reviews | last | if . == null then "none" else "\(.author.login) \(.state) \(.submittedAt)" end)\nlast commit: \(.commits | last | .committedDate)"'
   ```

   If the commit line is later than the review line, the approval is stale
   and the merge waits.

Do not treat a round you ran on your own PR as satisfying rung 4. It is
allowed, `/review` runs it, and it is useful before you hand the change
over - it just is not the review the merge waits on, for the reasons above.

## The reviewer side

A fresh Claude Code session in its own directory — never the author's
checkout and never a `--continue` of the author's session. The reviewer
directory on this machine is `~/PycharmProjects/Code-Review`; launched with
`claude-tm` there it registers on tubemail as `Code-Review-tm`, named by its
directory like every other worker. The GitHub identity is separate from the
worker name: `gh` acts as the reviewer because the session's environment
points `gh` at a second config directory whose `hosts.yml` (mode 600) holds
the reviewer token:

```bash
# once, in a plain terminal, never through a session (paste token, Ctrl-D)
mkdir -m 700 ~/.config/gh-ai-assistant-2026
GH_CONFIG_DIR=~/.config/gh-ai-assistant-2026 gh auth login --with-token
```

`claude-tm` loads the nearest `.env` at launch, so the reviewer directory
carries one line and no secret:

```
GH_CONFIG_DIR=/home/jesper/.config/gh-ai-assistant-2026
```

Never `GH_TOKEN=` in the environment: every Bash call in the session would
inherit it, and `env` in a transcript prints it. The reviewer can find its
own queue without being told:

```bash
gh pr list --repo <owner/repo> --search "review-requested:ai-assistant-2026" --json number,title,url
```

Then, per PR: `/review <PR>`. The skill posts a GitHub review — approve on
`APPROVE`, request changes on `REJECT`, a comment on `CAUTION` or `STOP` —
with the attribution line first and the full report collapsed beneath. On a
re-request it re-reviews under AR-3's rules: only the prior P0/P1 are
re-verified, nothing below P1 is raised, and `STOP` is returned if the
finding count did not fall.

## The reviewer identity

A GitHub machine user, not a GitHub App: one reviewer on a handful of orgs
does not need App installation tokens, and `gh` does not speak them without
a helper.

- Login `ai-assistant-2026`, on its own email alias, with 2FA.
- Member of each org whose repos it reviews (free plan: no seat cost), with
  write access on those repos — requested reviewers need at least read, and
  write keeps re-requests and labels simple.
- A **classic** personal access token with the `repo` scope and `read:org`,
  nothing else. Fine-grained tokens cannot reach repositories the account
  only collaborates on (they are limited to resources the token's own user
  or its organisations own), and this account is an outside collaborator on
  every repository it reviews. Record the expiry date in the ADR that
  introduced the identity and rotate before it.

GitHub refuses an approving review on your own PR. That is why one account
cannot do this: under a single token the review can only ever be a comment,
`reviewDecision` never changes, and nothing can be required.

## Branch protection

Enable after the identity exists and has approved at least one PR on the
repo, or that PR cannot merge. For a disciplin.run or personal repo:

```bash
gh api -X PUT repos/<owner>/<repo>/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["verify"]},
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null
}
JSON
```

Verify:

```bash
gh api repos/<owner>/<repo>/branches/main/protection --jq '.required_pull_request_reviews.required_approving_review_count'
```

For an InboundSavvy repo, `required_approving_review_count` is 2 (AI +
human), and the block gains `"require_code_owner_reviews": true`. Without
that key a `CODEOWNERS` file is inert: GitHub requests the owners but does
not require their approval, so two AI approvals would satisfy the count.
With it, one of the two approvals has to come from a code owner, which is
as close as GitHub gets to "one of them must be human" - list Andre and
Santiago there and nobody else. The rest of the rule stays prose here.

`enforce_admins` is false so an admin keeps an escape hatch for a broken
`main` at 2 a.m. Using it is reported as "merged without review" in the
done N/11 line, never silently.

## What "independent" is not

It is a different context window, usually of the same model family, holding
a different token. It is not a different reviewer in the human sense: it can
share a blind spot with the author that a person would not. The human
approval on InboundSavvy repos is the mitigation where the stakes warrant it.
