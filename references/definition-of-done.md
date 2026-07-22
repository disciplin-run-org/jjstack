# Definition of Done — "done-done"

The single canonical, version-controlled definition of what "done" means
across every jjstack session, worker, and work order. Skills and the
machine-local global `~/.claude/CLAUDE.md` cite THIS file as the source of
truth — when the definition changes, change it here first.

When someone asks "is it done-done?" — or when an agent claims anything is
done — this is the one checklist. ALL rungs, no exceptions.

## The 10 rungs

1. **Code complete** — implemented, no TODOs in the delivered path.
2. **Unit tests green** — written/updated and passing.
3. **Committed** (conventional message) **and pushed** to origin.
4. **Merged to main** — PR merged, dangling branch deleted.
5. **Deployed** — container/service rebuilt and restarted; the change is
   running live, not just sitting in git.
6. **QA green** — iris-qa BDD tests pass against the LIVE surface (where
   iris-qa covers the repo; otherwise the project's e2e equivalent).
7. **Documented** — specs updated (UX decisions), ADR filed via Architrix
   (architecture decisions), docstrings current.
8. **Released to consumers** — ready for the end-user acceptance test:
   loaded, integrated, observable in the real product.
9. **Change-log updated** — a high-level, end-user-facing summary of what
   changed this cycle appended to the project's change log (`CHANGELOG.md`
   or equivalent). Written for the person who USES the product, not the
   person who reads git history: what's new or different and why it
   matters, NOT the commit-level detail. If no change log exists yet,
   create one.
10. **README reflects current state** — the README describes the product
    AS IT NOW IS after this change (features, usage, setup, status). The
    README is a living description of the present product, NOT a change
    log — do not accrete a running history of edits into it; update the
    affected sections in place so a first-time reader sees today's truth.

## Reporting rule

The unqualified word "done" MAY ONLY be used when all 10 rungs hold.
Anything less is reported as **"done N/10"** naming the missing rungs
(e.g. "done 3/10 — committed+pushed; not merged, not deployed, no QA run,
changelog/README not updated"). Never make the human ask "did you push
it?" or "did you update the changelog?".

When a rung genuinely does not apply to a change (e.g. a docs-only change
has no deploy step, a rule-definition change has no unit-test surface),
say so explicitly in the report rather than silently dropping it — an
inapplicable rung is named, not omitted.

## Scope

This applies to every session and every worker (orchestrators, coders, UI
sessions) and to every work order written: put
"DONE = done-done (all 10 rungs) or report done N/10" in the order's Done
section.

## Where this lives

- **Canonical source:** this file — `references/definition-of-done.md` in
  the jjstack repo (`github.com/disciplin-run-org/jjstack`). Reachable at
  runtime through the `~/.claude/skills/jjstack` symlink.
- **Machine-local mirror:** the "Definition of Done" section of
  `~/.claude/CLAUDE.md` carries the full text so it is auto-loaded into
  every session. That mirror is hand-maintained and cites this file;
  update this file first, then reconcile the mirror.
- **Skills that cite it:** `verify-before-done`, `work-order`,
  `qa-build-loop`, and any skill whose completion gate references
  "done-done". Skills point here instead of re-inlining the full rung
  list, so a rung change touches this file (+ the CLAUDE.md mirror), not
  every skill.

## History

- Originated as an 8-rung checklist in the machine-local global
  `~/.claude/CLAUDE.md`.
- Extended to 10 rungs (added rung 9 change-log and rung 10 README) and
  captured here as the version-controlled canonical source.
