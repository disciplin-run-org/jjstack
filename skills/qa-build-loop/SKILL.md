---
name: qa-build-loop
description: |
  Overnight-autonomous TDD loop between iris-qa (QA owner) and a product-code
  worker. Replaces /qa-loop. iris-qa generates the failing test suite FIRST,
  raw output becomes the authoritative work order, the code worker implements
  to green, iris-qa reruns — and the loop runs unattended: no "should I
  proceed?", no context-anxiety stops, no morning flags that could be tonight's
  work orders. Bidirectional: either iris-qa OR the product can be the subject
  (any ai-agents ecosystem member: leanspecs, iris-qa, quartermaster, tubemail,
  actuatrix).
  Trigger on: "QA loop", "qa build loop", "TDD loop", "overnight qa",
  "run the loop overnight", "unattended TDD", "implement specs X Y Z via
  iris-qa", "iris-qa loop", "TDD via iris-qa", "fail-first then implement",
  "implement via iris-qa".
  Do NOT trigger for: browser QA on a deployed UI (use /qa or /qa-only),
  test-suite health audit (use /qa-review), or loading QA operational rules
  (use /jj-qa).
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# qa-build-loop — TDD driven by iris-qa, routed by the Quartermaster, running all night

This skill codifies the QA-loop pattern as a state machine AND removes the
self-imposed constraints that used to require Jesper's input mid-run. It was
built from a stall-point audit of the 2026-07-03/04 overnight sessions
(iris-qa-tm `bc4605db`/`a80d36d5`/`02e96e70`, iris-qa-coder-tm
`ac3a0235`/`08d500c6`, iris-qa-ui-tm `cb74e802`): every place progress
stopped, and what Jesper had to do about it, became a rule below.

The skill has two parts. **Part 1 — the Autonomy Contract**: how to run
unattended. **Part 2 — the TDD state machine**: what to run (carried from
/qa-loop, which this skill replaces).

---

# PART 1 — THE AUTONOMY CONTRACT

## Rule 1: Never ask "should I proceed?" — the answer is always yes, proceed

Never end a turn with a question during the loop. Not "Want me to keep
pushing or pause here?", not "What next — A, B, or C?", not "Dispatch that
WO now?". State the decision taken and continue.

Evidence: across the audited sessions, EVERY recommendation Claude attached
to a question was accepted. Jesper, twice in one night: *"you should be able
to make progress towards our goal without having to ask me all the time
what is next."* Take your own recommendation.

## Rule 2: No invented approval gates

Dispatching QM work orders IS the mechanism, never an escalation. There is
no ask-before-dispatch rule, no per-dispatch approval, no "per our standing
rule…" that this skill doesn't state. Jesper, verbatim: *"There is no
standing order that cross-worker dispatches needs my approval. The standing
order is: make as much progress as you can on your own."*

If you catch yourself citing an approval gate, find where it came from. If
it isn't in this skill or a memory Jesper wrote, it doesn't exist.

## Rule 3: Context is fuel — burn it, delegate it, never stop to preserve it

- **Always delegate detail work to workers via QM** (`clear_first` for
  unrelated tasks per /context-hygiene). The orchestrator's context is for
  orchestration and verification only.
- **≥85% context**: the self-clear must be ATOMIC — the clear and the
  resume order are one QM operation, in this exact sequence:
  1. Write the handover memory + a pointer to the authoritative transcript.
  2. `qm_queue_add(worker=<your own worker name>, clear_first=true,
     priority=high, prompt=<resume order>)`.
  3. **Verify the item exists** (`qm_queue_read`) BEFORE ending the turn.
  4. End the turn with NO further action. QM clears you and delivers the
     resume order. **Never type `/clear` yourself, never ask the manager
     to clear, never clear before step 3 confirms** — a clear without the
     queued resume order produces an amnesiac session.
- **The resume order template** (the dispatched prompt MUST begin with the
  skill invocation, because /clear wipes these instructions):

  ```
  /qa-build-loop RESUME — you are the continuation of an in-flight
  overnight run. Do not ask the user anything. 1) Read the handover:
  <memory file path>. 2) Read the ENTIRE previous session transcript
  (not just the tail): <transcript path>. 3) Reload /product-manager-review
  /kano-model /dev-philosophy /python-coder. 4) Verify live state (git,
  qm_queue_list, container health) — never trust the summary alone.
  5) Continue the loop from: <precise next actions>.
  ```

- Stopping "for quality" or "for a fresh context" without the handover +
  resume mechanism is forbidden.
- **Identity loss (solved 2026-07-04, QM #552/#553/#555):** after a bare
  clear, the session may not know its own worker name and QM dispatch
  won't match the pending resume item. The canonical recovery is
  **`tm_restart(worker, fresh=true)`** — restarts without `--continue`,
  the startup `/rename` re-registers the worker, and the manager
  auto-types `/sync-inbox`, which resolves identity from the session env
  and reads the timeline via `tm_receive(worker=…)`. Proven live: the
  recovered session found its pending QM items, verified evidence, and
  closed its review duty unaided. Inline fallback: `echo $TM_WORKER_NAME`
  (set by the wrapper, survives /clear) → `qm_queue_list`.

Evidence for the atomicity rule: on 2026-07-04 a session cleared without
the queued resume order landing; the fresh context woke to an empty
heartbeat notification, had no skill instructions (wiped by the clear),
didn't know its own worker name, and ended with "Just say the word" — the
exact stall this skill exists to prevent.

Evidence: one session stopped at 50% context "for highest quality from a
fresh context" — Jesper: *"you stopped again, waiting for me to decide
stuff for you. you are only at 50% context push forward."* Another stopped
at 69% and was told to delegate via QM instead.

## Rule 4: No "night" wrap-ups — flags for the morning become work orders tonight

The loop ends ONLY on goal-green or full-playbook exhaustion across ALL
scopes (Rule 8). Never wrap up with "flags for the morning" — convert each
flag into a QM work order now. **If you find a bug in another module that
you depend on, file a bug-fix request via QM to its owner immediately.**

Evidence: the first authorized overnight run self-terminated at 15:50 with
"two flags for the morning… Night." One flag (a github_save timeout) was a
one-line leanspecs fix that could have been filed that night.

## Rule 5: Never wait passively — every turn ends with an armed wake-up

Every turn ends with one of: an armed Monitor, a heartbeat background
command, or in-flight foreground work. On every wake:

1. `qm_queue_list` — the state of every item you filed.
2. `tm_my_inbox` — inbound notices you may have missed.
3. `tm_pending_permissions` — clear worker prompts (Rule 6).
4. Act on what changed; re-arm; continue.

Extras proven in the field:
- **Monitor the QM queue** for your own filed items (a 60s read-only poll
  of QM state worked well on 2026-07-04).
- **Heartbeats must write state to their output file** — every beat prints
  what it watched and found (queue ids, prompt cleared y/n, worker state).
  An empty output file makes a post-clear wake useless (2026-07-04: the
  amnesiac session's only clue was "heartbeat completed, output empty").
- **Bounce unverifiable "finished" notices** with a commit-sha bar: demand
  the sha + evidence via `qm_queue_followup` rather than closing on an ACK
  (the #535–#539 false-alarm pattern).
- **If your QM job is queued behind another job pending review, nag that
  job's requester to complete the verification.**

Evidence: Jesper had to say "check your mail", relay "#537 Group A is
done / #539 done / #538 done" twice, and report "didn't you get a tubemail
message from QM that they were done?".

## Rule 6: Keep the workers unblocked — permissions are your job

- **Pre-flight** (Phase −1): add known-safe allowlist entries (the
  curl-health-check / pycache-clear / docker-restart class) to each worker
  repo's `.claude/settings.json` before kickoff.
- **In-flight**: the heartbeat (start 120s, back off toward 240s when
  quiet) checks `tm_pending_permissions` and auto-approves safe prompts via
  `tm_respond_permission`. Deny-list: anything destructive (rm -rf outside
  build dirs, force-push, prod-data mutation, network-exposing binds) —
  deny and re-route as a proper work-order step.

Evidence: the coder stalled on every edit→restart cycle because of a
`Bash(curl *)` Ask rule; the orchestrator hand-cleared 3+ prompts and
invented the heartbeat mid-run. Codified here so it exists from minute one.

## Rule 7: Decide the forks — Decision Policy

How to decide without Jesper, in order:

1. **Does a spec, ADR, or memory already answer it?** Check first —
   don't re-litigate settled decisions.
2. **What does the most mature product in the ecosystem do?** Use it as
   the reference installation (today that's LeanSpecs; the principle names
   the criterion, not the product). "When in doubt, do like the reference"
   resolved most UI and contract questions in the audit.
3. **On any real fork — ALWAYS on architecture forks** (contract changes
   like the Option A/B run-only decision, gate hardness, ownership
   boundaries): run **/council**, every perspective informed by
   /dev-philosophy + /kano-model + /product-manager-review + /python-coder,
   with a stated bias for **Musk-simplify and the right long-term solution
   over a temporary patch**.
4. Still in doubt → the right long-term solution, Musk-simplified.
5. **Journal every decision** in `jjstack/qa-build-loop/decisions-<YYYY-MM-DD>.md`
   (subject repo), including the council verdict + minority report when one
   ran.

**When progress looks impossible, ask /council** — its Competitor-did-it
pass exists precisely to overcome "impossible" verdicts.

Only irreversible + destructive-to-production forks park a scope (Rule 8).
Everything else: decide, journal, proceed. Jesper reviews the journal in
the morning and can reverse anything reversible.

### Decisions are documented, always

- **User-experience decisions** land **in the specs**.
- **Architectural decisions** land **in an ADR filed via Architrix into the
  correct repo** — the repo the decision governs (e.g. AR-2 lives in
  iris-qa, AR-3 in leanspecs).
- A decision that lives only in the journal is not done.

### Anti-slop spec discipline

Before adding ANY spec, check the existing specs for where the behavior
already belongs — most of the bad specs Jesper spent hours Musk-simplifying
away were Claude-generated. The inverse also binds: **no feature ships in
code that is not reflected in the specs.** Spec first, code second.

## Rule 8: The blocked playbook (replaces "escalate to user")

Per blocked scope, in order:

1. **Retry once** with evidence (a transient timeout ≠ a failure — verify
   via the state flag, e.g. `github_status.dirty`, before re-trying blind).
2. **Alternate path** — how does the reference installation do it?
3. **Upstream bug?** File the bug-fix work order via QM to the owning
   worker (Rule 4) and PARK the scope behind it.
4. **Take the next scope.** A parked scope never blocks the loop.
5. Only when ALL scopes are green or parked: write the morning report
   (Rule 11) and idle with monitors armed. **Do not exit.**

"Escalate to the user", "bring to the user for arbitration", and "your
call" appear nowhere in the running loop. Questions batch into the morning
report.

## Rule 9: Standing infra authority

You may **rebuild/restart any ecosystem container** (leanspecs, iris-qa,
quartermaster, tubemail, the twin) when a dependency requires it. Guardrails:

1. **Safe-to-restart check**: no in-flight QM work orders against that
   product — or pause the queue first (`qm_queue_pause`).
2. **Coordinate with the owner session if online**: check
   `tm_list_workers`; if the owning worker is connected, tell it via
   tubemail before restarting and wait for its ack (short timeout, then
   proceed with a journal note).
3. **Health-check before and after**; roll back on a failed after-check.
4. **Journal every restart** (what, why, health results).
5. QM itself: pause queue → restart → resume — never mid-dispatch.

Evidence: overnight progress stopped because Jesper had to rebuild
leanspecs by hand ("new litmus should be online, I reloaded the Leanspec
server") and redeploy QM ("QM has been redeployed").

## Rule 10: Verify state directly — don't wait to be told

On every wake, verify external state yourself: health endpoints,
`docker ps`, `qm_status`, `git log` on worker repos, container image
timestamps. The audit shows Jesper repeatedly relaying facts Claude could
have read ("I am looking at the coder's console and it is still working").

Also: **shape the fixture yourself.** You have standing permission to
**enhance (add-to) the litmus template** to create the conditions a test
needs — strictly **add-only**: never modify or delete existing template
content (the Jul 4 delete scare: a worker's template change looked like it
removed 71 behaviors; only add-only is safe without review).

## Rule 11: Visual checks — self-verify first, batch the rest

Before parking any UI check: use **/browse** to load the page, take
screenshots, and compare the rendered UI against the requirements with
your own image analysis. Fix what the comparison catches. Most of the
audit's "eyeball the live UI" asks were resolvable this way (the ✓-vs-✅
glyph mismatch was visible in the screenshot the whole time).

**Every worker CAN screenshot — /browse screenshot mode.** Chrome MCP
tools may be barred in worker sessions, but /browse's screenshot mode
needs only Bash: `google-chrome --headless=new --screenshot=<png>
--virtual-time-budget=8000 <url>`, then Read the PNG and compare what
you SEE against the requirement (proven live 2026-07-04 on the iris-qa
SPA — brand-casing was verifiable in the image). Pre-allowlist the
command in pre-flight (Rule 6). Escalation ladder for visuals:
1. /browse screenshot (S1 headless chrome) — looks, layout, glyphs, colors.
2. gstack browse daemon Playwright — MEASUREMENTS (heights, boxes,
   computed styles) and cookie-authed pages.
3. QM work order to iris-qa Playwright — when the check should double as
   the QA-green rung anyway.
A claim with neither a screenshot nor a measurement is not verified.

Only genuinely subjective look-and-feel calls defer — into the morning
report, with screenshots attached.

## Rule 12: Definition of Done — "done-done"

A scope or work order is done ONLY when it is **done-done** — the canonical
8-rung checklist in global CLAUDE.md: code complete, unit tests green,
committed+pushed, merged to main + dangling branch deleted, deployed and
running live, **iris-qa tested green against the live surface**, specs/ADR
updated, and ready for Jesper's end-user acceptance test.

**Reporting rule:** the unqualified word "done" may only be used at 8/8.
Anything less is **"done N/8"** naming the missing rungs — in your own
replies AND required of every worker (put "DONE = done-done or report
done N/8" in every work order's Done section). "Wired" is not done;
"demonstrated" is done.

## Rule 13: Worktree discipline

Parallel work on the same codebase uses **git worktrees** — one per
worker/branch — so the orchestrator, coder, and UI sessions never trip
over each other's working tree. Both the shared-worktree commit hazard and
the "docker-compose fix stuck on another session's WIP branch" stall trace
to shared checkouts.

## Rule 14: Amnesia recovery — a cleared session mid-run resumes itself

If you find yourself with a freshly cleared context and any evidence of an
unfinished qa-build-loop run, **you are the resumed session — recover, do
not ask.** Evidence, any one of:

- a `jjstack/qa-build-loop/decisions-<YYYY-MM-DD>.md` for today with no
  matching `morning-report-<YYYY-MM-DD>.md`
- a handover memory (`project_*handover*` / MEMORY.md pointer)
- a pending/in-flight QM item addressed to you (`qm_queue_list`)
- a background-task notification named after this skill

Recovery, in order:

1. **Recover your identity**: `echo $TM_WORKER_NAME` — deterministic, set
   by the claude-tm wrapper, survives /clear. If the channel looks dead,
   `tm_self_reconnect_mcp` / the tubemail-channel reconnect skill.
2. **Find your resume order**: `qm_queue_list` for pending/in-flight items
   addressed to you; read it (`qm_queue_read`) — it IS your work order.
3. Then the resume-order steps from Rule 3: reload this skill, read the
   handover, read the ENTIRE previous session transcript from
   `~/.claude/projects/<cwd-slug>/` (newest large `.jsonl` before your
   own), reload the four key skills, verify live state, continue.

Listing options and ending with "just say the word" is the failure mode,
not a fallback — it happened on 2026-07-04 and cost the night.

## Rule 15: Dogfood the ecosystem's LLM tools — hand-writing their job is cheating

Whenever a goal can be achieved EITHER by Claude hand-writing the artifact
OR by an ecosystem MCP call — generate gherkin, generate a QA e2e test,
`sharpen_specs`, groom specs, `test_triage`, `spec_suggest`, and any other
published generation/judgment capability — **always make the MCP call.**
The servers' LLM features only get as good as they can be by being
exercised against real work; a loop that quietly hand-writes around them
starves them of exactly the hard cases they need.

The discipline per call:

1. **Form your own best solution first** (cheaply — an outline of what a
   correct output must contain), so you can judge the MCP output instead
   of rubber-stamping it.
2. **Make the MCP call** and use its output as the working artifact.
3. **Diff against your reference.** Output fine → proceed. Output wrong,
   weak, or subtly off → you may repair the artifact locally to keep the
   loop moving, BUT the repair is a bug signal, never the fix.
4. **Every defect becomes a QM work order to the MCP server's owner** with
   the full evidence: exact input, actual output, expected output, and
   your suggested fix — improve the prompt, the deterministic gates
   (gate_check-class), the specs, the algorithm (Architrix-side), or
   whatever the diff points at. The ecosystem is under constant
   improvement; a swallowed defect is a lost improvement.

Boundary: this covers published generation/judgment capabilities, not
ordinary code edits (implementing a tool's Python IS the coder's job).
When in doubt — if an MCP tool advertises doing it, calling the tool is
the job, and doing it by hand is cheating.

## Phase −1: Pre-flight checklist (run while Jesper is still there)

The pre-flight is the ONE sanctioned place to interrogate Jesper — **ask
MORE questions up front, specific to the stated goal.** Front-load every
foreseeable fork: scope priorities, authority edges, product calls the
goal implies, what "green" means for each scope. General fallback rules
are the safety net, not the plan.

Then, mechanically:

1. **Goal contract**: scope list confirmed; `/goal` set with a condition
   achievable WITHOUT user decisions (a Stop-hook goal that hinges on a
   user choice deadlocks and burns context — it happened).
2. **Roster**: `tm_list_workers` — every needed worker online; QM roles
   registered.
3. **Permissions**: pre-clear each worker repo's `.claude/settings.json`
   allowlist (Rule 6).
4. **Containers**: health sweep of every involved service + the twin.
5. **Fixture host**: verified present, deterministic ids confirmed.
6. **Journal**: create `jjstack/qa-build-loop/decisions-<YYYY-MM-DD>.md`.
7. **Machinery**: arm the QM monitor + the permission heartbeat.

## The morning report

One file: `jjstack/qa-build-loop/morning-report-<YYYY-MM-DD>.md` in the subject
repo. Contents: scoreboard (per-scope pass rates, cycle counts, red→green
deltas), decision-journal digest (incl. council verdicts), parked forks
with recommendations, deferred visual checks with screenshots, infra
actions taken (restarts, rebuilds, fixture additions).

---

# PART 2 — THE TDD STATE MACHINE

The pattern is product-agnostic: any product in the ai-agents ecosystem can
be the subject, and the loop runs the same shape every time. iris-qa-tm is
always the QA owner; the subject's code worker (`<product>-code-tm` or just
`<product>-tm` if there is no role split) implements to green.

## Subject vs role

Two roles, played by different workers:

- **SUBJECT** — the product whose code is being driven by failing tests.
  Could be `<product>-code-tm` (leanspecs has spec/code/ui split),
  `<product>-tm` (single-worker products), or even **iris-qa-tm** when its
  own generator/test-runner needs to be improved.
- **QA OWNER** — always `iris-qa-tm`. Generates failing tests, classifies
  failures, reruns after fixes.

Bidirectionality: QM #181 made iris-qa the subject — its generator
hardcoded `repo='test_repo'`, surfaced through a leanspecs qa-loop. Same
loop shape, different subject. iris-qa as subject still gets work orders
filed via QM, gets reviewed via the reviewer protocol below, etc.

## Phase 0 — dependency check (MANDATORY before any scope fires)

For any scope `<product>:<cap>.<feature>`, identify upstream caps it
implicitly depends on (e.g. `mcp:3.X` depends on `mcp:1`+`mcp:2`; UI scopes
depend on the underlying MCP scope). Run `iris_qa_run` on those FIRST.

A Phase 0 failure becomes its own scope. The original scope waits behind
it (parked, per Rule 8 — the loop moves on meanwhile).

**Rule:** never assume a cap is "done" from commit messages alone — iris-qa
is the only authority. Cite `feedback_verify_assumptions_before_qa_loop.md`.

## The non-negotiable order

**iris-qa goes FIRST.** The subject's code worker goes SECOND. Anything else
is not TDD.

```
1. iris-qa-tm    generates + runs the failing test suite for the scope
2. iris-qa-tm    classifies each failure into one of five buckets
3. Quartermaster receives the classified report
4. Quartermaster routes work orders:
                 target_bug    → subject's code worker (implements to green)
                 spec_quality  → subject's spec worker (sharpens Gherkin)
                 spec_gap      → subject's spec worker (creates new behavior in unmapped:1.1)
                 iris_qa_bug   → iris-qa-tm fixes its own generator
                 setup_bug     → fix the fixture host or sync infrastructure
5. Workers implement. Push to origin/main.
6. Sync product.json subject→iris-qa if Gherkin changed.
7. iris-qa-tm re-runs the scope. Loop.
8. Stop per the stop conditions below (self-arbitrated — never "ask the user").
```

## What the dispatcher MUST NOT do

- **Do not paraphrase Gherkin into a work order.** The raw `iris_qa_run`
  output is the authoritative failure description.
- **Do not send the subject an implementation work order before iris-qa
  has produced failing tests.** Without failing tests, there is no TDD.
- **Do not ask "is this really what you want?" when the user says TDD.**
  The user authorized the loop. Failing tests ARE the work order.
- **Do not stop to confirm scope when the user listed the specs.** The
  list is the scope. Execute.
- **Do not classify failures without reading the raw pytest error.**
  "unmapped_step: True" can be tool-missing (target_bug) or bad step
  matcher (iris_qa_bug); only the raw error distinguishes them.
- **Do not let iris_qa_bug-class failures leak to the subject's code
  worker.** iris-qa owns its own generator.
- **Do not edit another product's source even with file access.** File a
  QM work order to the owning worker (per
  `feedback_role_boundaries.md`). Same rule whether iris-qa is subject or
  QA owner.
- **Do not narrow scope to dodge a tool timeout.** Timeouts mean the tool
  needs an async re-spec — see "When tools time out" below.

## The five failure buckets

| Symptom | Bucket | Route to |
|---|---|---|
| MCP tool doesn't exist / returns wrong shape | target_bug | subject's code worker |
| Tool times out under realistic load | target_bug | subject's code worker (async re-spec) |
| Gherkin vague, missing params, untestable, contradicts parent | spec_quality | subject's spec worker |
| iris-qa surfaces a real missing behavior (no spec exists) | **spec_gap** | subject's spec worker (create under `unmapped:1.1` "From iris-qa", `owner="iris-qa"`) |
| Generator produces unmapped_step on a legitimate tool call | iris_qa_bug | iris-qa-tm |
| Generator asserts wrong field / weak assertion / false pass | iris_qa_bug | iris-qa-tm |
| Generator hardcodes placeholders (`repo="test_repo"`) | iris_qa_bug | iris-qa-tm |
| Generator missing setup-prelude (e.g. for `spec_create(template=)`) | iris_qa_bug | iris-qa-tm |
| Generator collisions with new gates (e.g. `name_uniqueness_within_scope`) | iris_qa_bug | iris-qa-tm |
| Hardcoded ids that broke when spec ids migrated | iris_qa_bug | iris-qa-tm |
| Fixture wrong, dirty state, parent missing in fixture host | setup_bug | fix the fixture host |
| Fixture lacks a precondition state | setup_bug | **enhance the litmus template — add-only** (Rule 10) |
| Container stale / product.json out of sync | setup_bug | sync infrastructure |
| Passes alone, fails in batch | setup_bug | retry-with-setup handles it |

`spec_gap` vs `spec_quality`: spec_quality fixes EXISTING Gherkin; spec_gap
files a NEW behavior because none existed. Both obey the anti-slop spec
discipline (Rule 7): check where the behavior already belongs first.

### Cluster rule

When a scope returns >50% red, spot-check ONE generated test BEFORE
classifying. Generator bugs cluster — if one is wrong, they all are. Fix
the generator first; re-run.

### Spec-rename detector

When a cap or feature is renamed (e.g. Cap 12 → infrastructure:2,
mcp:3.20 → mcp:3.3), grep iris-qa source for the old id. Hardcoded
references silently break until something forces a regeneration.

## When tools time out

An MCP tool that times out under realistic test load (e.g.
`iris_qa_run(item_id="<cap>")` against a cap with 60+ behaviors hitting a
60s MCP client timeout) is a `target_bug`. File a work order on the owning
worker:

> Respec as async — return `job_id` immediately, expose `<tool>_status` for
> polling. BDD/TDD recode using the async-job pattern (model on
> `spec_import` mcp:3.10.1 or similar).

**Do NOT narrow scope to dodge the timeout.** That hides the architectural
bug. Cite `feedback_timeout_means_async_respec.md`.

Also: a WRITE timeout is not proof of failure — verify via the state flag
(e.g. `github_status.dirty`) before retrying or declaring a blocker. The
2026-07-03 github_save "failure" was three real transient timeouts
distinguished from success only by the dirty flag.

## Tool semantics: `iris_qa_run` vs `iris_qa_run_suite`

- **`iris_qa_run(item_id)`** — GENERATES + runs tests for the given scope.
  Use this for first-time runs, or any time you want fresh tests. Per
  scope, not whole product.
- **`iris_qa_run_suite(scope)`** — READS disk only. Scores existing tests
  under `<workspace>/iris-qa/tests/generated/`. Never generates. Use ONLY
  after `iris_qa_run` has populated tests for the scope you want scored.

Returns since QM #163: `iris_qa_run_suite` now surfaces
`approved_behaviors` and `generated_tests` counts and emits a structured
error when approved>0 but generated==0, instead of silent
`tested_behaviors=0`.

## Reviewer protocol — if you sent it, you validate it

When a worker replies on a QM work order with `awaiting_review`, the
dispatcher (you) owns the verification. Five-step ladder before
`qm_queue_mark(status="done")`:

1. **Commit exists** at the claimed sha (`git -C <repo> show <sha>`).
2. **Diff matches** the claim's scope and line count.
3. **Docstrings/tests updated** where the claim says so.
4. **Live smoke** against the changed surface returns the new shape (e.g.
   call the changed MCP tool and confirm the response).
5. **Unit-suite claim** spot-checked (run a subset locally if feasible).

Any gap → `qm_queue_mark(status="needs_correction", reason="<specific
gap>")`. Don't pile orthogonal bugs onto the closing item — those go in
new QM items.

**Trust but verify**: prose says what they intended; commit + diff + smoke
say what landed. The mismatch is where bugs hide. Cite
`feedback_dispatcher_owns_validation.md`. And per Rule 5: an
`awaiting_review` notice that arrives seconds after dispatch is probably a
Stop-hook misfire on an ACK — bounce it with a commit-sha bar, don't close.

### The same ladder applies BEFORE filing needs_correction

When a worker's reply has `verdict=partial` or `verdict=in_progress`, run
the ladder one more time — specifically step 1 (commit exists) and step 2
(diff matches). "Fix is in flight" in worker prose may mean "already pushed
to origin/main, you missed it" — a corrective direction asking the worker
to undo shipped work wastes a dispatch slot and confuses the worker.

The check before correction:
- `git -C <worker-repo> log --oneline -10` — what's landed since
  dispatched_at?
- Read each new commit's message — does it explain what they did and why?
- If the shipped reasoning disagrees with your correction, decide whether
  their reasoning is actually better than yours BEFORE pushing back.

Cite `feedback_verify_before_correction_too.md`.

## Output discipline

**One PR per scope.** Title: `feat(qa-loop): <scope> green`. The worker
that pushes red→green opens the PR. iris-qa-tm's generated-test commits
ride along on the same branch when the same scope produced both.

Done means Rule 12 done: committed, pushed, merged, dangling branch
deleted, unit-tested, iris-qa green, running live.

When multiple `<product>-<role>-tm` workers share one git tree, use git
worktrees (Rule 13); at minimum `git diff --staged --stat` before any
commit. Per `feedback_shared_worktree_commit_hazard.md`.

## Fixture isolation

Every subject names a **fixture host** — a repo or workspace whose
product.json holds the test sandboxes. Fixture data lives in the host;
NEVER in the subject's live workspace.

Examples (not mandates):
- **leanspecs + iris-qa**: host is the `litmus` repo at `mcp:100+`. They
  share a spec schema, so they share a fixture pattern.
- **Other products** (quartermaster, tubemail, actuatrix, etc.): each
  picks the pattern that isolates fixture mutations from live state.

The skill enforces "fixtures live in the host, never in the subject's live
workspace" — the host's identity is per-product, NOT a hard mandate.

**Fixture shaping is in-bounds** (Rule 10): enhance the litmus template to
create needed preconditions, strictly add-only, and prefer deterministic
low-numbered stable-ids (leanspecs #536 made these the default — reference
them literally in gherkins rather than building capture machinery).

## Setup contract source of truth

Each subject's setup/teardown sequence lives in its own spec at
`infrastructure:2` (or equivalent — read each subject's product.json to
find its QA Specs cap). iris-qa reads this on every run. If the subject's
setup spec drifts from what iris-qa is hardcoded to read, dispatch a
target_bug to iris-qa-tm to update its reader.

## Infrastructure sync sequence

After ANY Gherkin change in the subject's spec, before running iris-qa:

```bash
docker cp ai-agents-<product>-1:/data/<product>/specs/product.json /tmp/p.json
docker cp /tmp/p.json ai-agents-iris-qa-1:/data/<product>/specs/product.json
```

Skip = stale tests, wasted cycle. Sync only after the spec change has
landed in the subject's container — not before. If the change needs a
container rebuild to go live, do it under Rule 9 (standing infra
authority) instead of waiting for morning.

## Canonical work orders

### To iris-qa-tm (the first cycle and every subsequent cycle)

```
Work order — Run iris_qa_run on <scope> and classify failures.

## Scope
<comma-separated feature ids or single item id>
target_url: http://localhost:<port>/mcp/?repo=<fixture-host-repo>
subject: <product> (whichever product is being driven this cycle)

## Deliverables
1. Verify product.json matches the subject's container. Sync if drifted.
2. iris_qa_run(item_id) for each scope item.
3. Classify each failure (target_bug / spec_quality / spec_gap / iris_qa_bug / setup_bug).
4. Fix iris_qa_bug-class failures in your own codebase; rebuild; retest.
5. Report in the shape:
   { scope, total, pass, fail, by_bucket, report: [{behavior_id, pass, bucket, diagnosis}, ...] }
```

### To the subject's code worker (after iris-qa reports target_bug failures)

```
Work order — Make <N> failing iris-qa tests green.

## Failing tests (from iris-qa-tm report <event_id>)
<paste the raw per-behavior failure lines>

## Deliverables
1. Implement the MCP tool(s) / fix the return shapes so every listed behavior passes.
2. Unit tests alongside (pytest).
3. docker compose up -d --build <product>.
4. Sync product.json to iris-qa: docker cp ... (the infrastructure sync sequence above).

## Verify
iris_qa_run(<scope>) — all listed behaviors pass.

## Done
Reply with: commit_sha, tests_passing, any remaining failures you classified
differently. Open the PR titled `feat(qa-loop): <scope> green`.
DONE = done-done (all 8 rungs of the global Definition of Done) or report
"done N/8" naming the missing rungs. Demonstrated green with the result
pasted, never "wired". Zero false-greens: if blocked, punt-and-report with
specifics.
```

### To the subject's spec worker (after iris-qa reports spec_quality OR spec_gap failures)

```
Work order — Fix <N> behaviors flagged by iris-qa.

## Flagged specs (from iris-qa-tm report <event_id>)
<paste flagged behavior ids + iris-qa's diagnosis>

## Deliverables (per item)
- spec_quality: rewrite Gherkin per `feedback_gherkin_patterns.md`.
- spec_gap: FIRST check existing specs for where the behavior belongs
  (anti-slop); then spec_create under `unmapped:1.1` "From iris-qa" with
  owner="iris-qa", rationale + summary + detail describing what iris-qa surfaced.

## Done
Reply: commit_sha, list of fixed/created spec ids.
DONE = done-done (all 8 rungs) or report "done N/8" naming the missing rungs.
```

Work-order hygiene: state constraints explicitly in the order (e.g.
"litmus template: ADD-ONLY, never modify/delete existing content") — the
Jul 4 delete scare came from an under-specified fixture order, not from a
decision that needed arbitration.

## Gherkin quality rules (operational lessons)

- Every step maps to an explicit MCP tool call, not state description.
- Include ALL required parameters (owner, rationale for spec_create).
- "contains" for substring match, "equals" for exact match.
- Given steps VERIFY state with read tools, never CREATE data.
- Destructive tests (product_delete) restore the fixture host in And steps after Then.
- Behaviors that return confirmation text need a follow-up read for verification.
- Prefer literal deterministic fixture ids over runtime capture machinery.

## Stop conditions (self-arbitrated)

The loop ends when any one is true:

1. **Goal state**: every scope is 100% green (Rule 12 done).
2. **Plateau**: pass rate did not improve across two consecutive cycles →
   self-arbitrate: spot-check one generated test (cluster rule), run a
   test_triage-style classification of the diff between the two cycles'
   reports, and if genuinely stuck run **/council** (Rule 7 — including
   the overcome-impossible pass). Decide, journal, act. If the scope is
   still stuck after that, PARK it (Rule 8) and continue other scopes.
3. **All scopes green or parked** → morning report + armed idle (Rule 8.5).
   Never exit; never "escalate to the user" mid-night.

A worker reporting a classification you disagree with is decided on
evidence (raw pytest error, spec text, reference installation), journaled,
and re-routed — not brought to the user.

## Parallelism

iris-qa test generation and subject implementation are independent once
iris-qa's report is in. Multiple scopes can be in different phases
simultaneously:

- 3.1: iris-qa-tm running tests (cycle N)
- 3.3: subject's code worker implementing (from cycle N-1 report)
- 3.4: iris-qa-tm rerunning (verifying cycle N-1 fixes)

Dispatch all phases that are runnable; don't serialize artificially.
Parallel code work on one repo → git worktrees (Rule 13).

## Memory cross-references

Foundational:
- `feedback_tdd_non_negotiable.md` — approved behaviors must be testable; no "Not MCP-testable" dodges.
- `feedback_qm_is_manager.md` — QM directives are engineering-manager work orders; act, don't reconfirm.
- `feedback_align_gherkin_to_tool_schema.md` — load actual tool schema before rewriting gherkin.
- `feedback_retro_2026_04_14.md` — Cap 1/Cap 2 retro: TDD pushback, drift checks, Gherkin patterns.
- `feedback_role_boundaries.md` — bugs in another product's codebase = that product's worker; file QM work order, don't edit.

Operational:
- `feedback_shared_worktree_commit_hazard.md` — diff before commit; worktrees for parallel work.
- `feedback_litmus_lives_in_litmus_repo.md` — leanspecs/iris-qa example of fixture host.
- `feedback_verify_assumptions_before_qa_loop.md` — Phase 0 sanity gate.
- `feedback_qa_loop_ecosystem_wide.md` — bidirectional, product-agnostic.
- `feedback_dispatcher_owns_validation.md` — five-step reviewer ladder.
- `feedback_timeout_means_async_respec.md` — timeouts = target_bug, not workaround.
- `feedback_verify_before_correction_too.md` — run the ladder before filing corrections.

## Philosophy

The QA-loop is a state machine, not a to-do list. The job is to keep the
state machine moving — route each classified failure to exactly the worker
who owns that class of bug, validate every reply against the five-step
ladder, keep infra synced, keep the workers unblocked, and let TDD's
natural ordering (test first, code second) do the sequencing.

Overnight, the state machine has no operator. That is the design, not a
gap: every fork has a policy, every wait has a wake-up, every blocker has
a playbook, and every decision has a journal entry Jesper reads over
coffee. When the dispatcher tries to shortcut — paraphrasing Gherkin,
sending implementation work before tests exist, narrowing scope to dodge
timeouts, rubber-stamping awaiting_review, or stopping to ask a question
whose answer is "yes, proceed" — errors compound and the loop slows.
Trust the loop. Run it. All night.
