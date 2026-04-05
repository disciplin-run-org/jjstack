---
name: jj-qa
description: >
  QA philosophy and operational rules that apply to all testing work. Enforces cleanup
  discipline, Docker-first execution, framework-driven debugging, and Kano-level test
  depth. Use alongside gstack's /qa for browser testing, or standalone for API/integration
  testing. Trigger on any QA, testing, or quality assurance work.
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

# jj-qa — QA Philosophy & Operational Rules

This skill defines QA principles that apply to ALL testing work — browser testing,
API testing, integration testing, and production monitoring. It complements gstack's
`/qa` (which handles browser-based test-fix-verify loops) by adding operational
discipline that gstack does not enforce.

**How this coexists with gstack `/qa`:**
- gstack `/qa` = browser testing methodology, issue taxonomy, scoring, fix-verify loop
- jj-qa = operational philosophy: cleanup, Docker, framework-driven debugging, Kano depth
- Use both together: run `/jj-qa` first to set the rules, then `/qa` for browser testing
- Or use `/jj-qa` standalone for API/integration/container testing

---

## Rule 1: QA Must Clean Up After Itself

All test data created during QA MUST be reversed/deleted after testing. No leftover
state in databases, containers, or APIs.

**Before creating any test data:**
- Snapshot the current state (record IDs, counts, or checksums)

**After testing completes (pass OR fail):**
- Delete all test-created records by ID
- Use DELETE endpoints to remove API-created resources
- Restore any modified state to pre-test values
- Verify cleanup succeeded

**Hard rules:**
- QA changes must be non-destructive — never modify or delete existing user data
- Log entries are the ONLY acceptable permanent side effect
- If cleanup fails, warn the user explicitly — never silently leave test data behind
- This applies to both browser testing AND API integration testing

**Reversibility principle:** Every action QA performs must have an inverse action available.
If you cannot reverse an action, do not perform it during QA without explicit user approval.

---

## Rule 2: Always Run in Docker

Never run services locally for testing. Always use Docker containers.

- Use `docker compose` without asking — never offer "run locally" as an option
- Test against containerized services, not local processes
- If containers are not running, start them: `docker compose up -d`
- This ensures tests run against the same environment as production

---

## Rule 3: All Diagnostics Go Into the Framework

When you need to debug a failure, do NOT run ad-hoc commands in the terminal.

- If the project has `check.py` or `heal.py`: add new diagnostic checks there
- If neither exists: create `debug/heal.py` using the `/heal` skill
- Every debugging insight must be captured in the framework
- Always show the full script output — never pipe through sed/grep to filter sections
- See `/heal` skill for the full framework pattern

---

## Rule 4: All Fixes Go Into the Framework

When you identify a remedial action to fix an issue:

- Do NOT run it as a one-off command
- Add it as a heal step in the appropriate test script
- Re-run the framework to verify the fix works
- The fix must be repeatable — if the problem recurs, the framework fixes it automatically
- Rebuilds are valid: `docker compose build <service>` is a legitimate heal action

---

## Rule 5: Kano-Level Test Depth

Not all features deserve the same testing depth. Match test investment to feature importance.

**CRITICAL: These numbers are MINIMUMS, not targets.** The table below defines the
absolute floor — the least amount of testing acceptable before shipping. More testing
is always encouraged. An AI or developer who stops at these numbers is doing the bare
minimum. Exceed them whenever possible.

| Kano Level | Category | MINIMUM Test Depth (floor, not ceiling) | Quality Tolerance |
|-----------|----------|----------------------------------------|-------------------|
| 1 | Security | AT LEAST 100% use cases + 100% corner cases | Zero — disable feature if broken |
| 2 | Core | AT LEAST 100% use cases + 95% corner cases | Zero |
| 3 | Auxiliary | AT LEAST 100% use cases + 75% corner cases | Broken 1-2 days ok |
| 4 | Performance | AT LEAST lab + production measurement | 10% dip ok for 2 weeks |
| 5 | Bells & Whistles | AT LEAST 100% use cases + 50% corner cases | Broken 5 days ok |
| 6-10 | Lower priority | AT LEAST 100% use cases | Varies |

When writing tests, ask: "What Kano level is this feature?" and use the table to
determine the **minimum** test depth. Then consider: what additional tests would
catch bugs that the minimum would miss? Add those too. The table sets the floor —
your job is to build above it.

---

## Rule 6: Dual-Axis Test Categorization

Every test should be categorized on two axes:

**test_target** (what is tested):
api, seo, content, network_layer, accessibility, performance, security, database,
authentication, authorization, integration, ui, etc.

**test_scope** (how it is tested):
functional, smoke, integration, regression, e2e, security, load, stress, etc.

This enables targeted test runs (e.g., "run all security tests" or "run all smoke tests").

---

## Rule 7: Regression Gate Tracking

Once a test has passed, it MUST keep passing:

- Track which tests have passed at least once (`first_pass` timestamp)
- Once a test passes, it enters `regression_locked` state
- New code cannot be merged if it breaks a `regression_locked` test
- This prevents quality from silently degrading over time

---

## Rule 8: Grading & Release Gates

**Test grading:**
- Excellent: >= 90% passing
- Good: >= 75% passing
- Degraded: >= 50% passing
- Critical: < 50% passing

**Release gates:**
- **LAUNCH**: All categories above threshold
- **DEGRADED**: Some below threshold, none critical — ship with known issues
- **BLOCKED**: Any category below 50% — do not ship

---

## Workflow: Using jj-qa with gstack /qa

When doing browser-based QA testing:

1. Run `/jj-qa` to load these rules into context
2. Run `/qa` to execute gstack's browser testing methodology
3. During `/qa`, these rules apply automatically:
   - Clean up any test data created via forms or APIs
   - Run all services in Docker
   - Any debugging goes into heal.py, not ad-hoc commands
   - Any fixes go into the framework, not one-off patches

When doing API/integration/container testing without a browser:

1. Run `/jj-qa` as the primary skill
2. Write tests following the dual-axis categorization
3. Use the heal framework for debugging and fixes
4. Apply Kano-level depth based on feature importance
5. Enforce regression gates before merging
