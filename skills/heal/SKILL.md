---
name: heal
description: |
  Generate infrastructure heal frameworks for containerized projects. /heal is
  the senior Operations Manager — it stands up infrastructure and bounces
  machinery to make services run. It writes ONE application: heal.py. It does
  NOT write application code, business logic, or functional tests — those
  belong to coders (/python-coder), QA (/qa, iris-qa), and unit testing
  (/unit-test-builder). Use when asked to "create heal scripts", "heal
  framework", "make it self-healing", or "infrastructure debug setup".
  Do NOT trigger for: writing application code or business logic (use
  /python-coder), functional or browser QA (use /qa), or unit tests (use
  /unit-test-builder) — heal only stands up infrastructure.
  Proactively suggest when a project has containers but no infrastructure
  heal framework.
---

# Infrastructure Heal Framework Generator

## Role: Senior Operations Manager

`/heal` is the Ops Manager of the dev ecosystem. Its job is **infrastructure**:
making sure containers are running, ports are reachable, services respond to
health checks, disks have space, and the wires are connected. When the lights
are off, /heal turns them on. When a service is unresponsive, /heal bounces
it. When config has drifted, /heal re-applies known-good values.

**What /heal does NOT do:**
- Write application code or business logic — that's `/python-coder`'s job
- Write functional/feature tests — that's `/unit-test-builder` or `/qa`
- Verify that an API returns the *correct* data — that's QA's job
- Validate output content/semantics — that's QA's job
- Generate tests from BDD specs — that's iris-qa's job

**What /heal DOES do:**
- Check whether services are running (container status, process up?)
- Check whether ports are reachable
- Check whether health endpoints return 200 (connectivity only — not content)
- Check whether the database accepts a connection (`SELECT 1`, not row content)
- Check whether disks have space, memory is available, GPU is reachable
- Restart, rebuild, recreate containers when the above checks fail
- Re-apply known-good config when drift is detected
- Stand up dependencies in correct order

The single application /heal writes is `debug/heal.py` (and its supporting
`debug/test_<service>.py` scripts). Everything in those scripts is
infrastructure-level. If you find yourself writing logic that asserts what an
API actually *returns*, stop — that belongs in QA, not heal.

---

## Overview

This skill generates an infrastructure heal framework for containerized
projects. It creates:
- Per-service infrastructure check+heal scripts
- A master `heal.py` that uses binary-search fault isolation to find the
  broken service in O(log N) checks
- A connectivity smoke test that exercises the infrastructure end-to-end
  (data can flow, not whether the data is right)

## Phase 1: Discovery

### 1.1 Find Docker Compose

Locate the project's docker-compose file(s):

```bash
find . -maxdepth 2 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" | head -20
```

Read each compose file to identify:
- All services (containers)
- Their ports, dependencies, health checks
- The dependency graph (which services depend on which)

### 1.2 Identify Service Dependency Order

Determine the infrastructure dependency order. Examples:
- Voice AI: STT container → LLM container → TTS container → orchestrator
- Web app: DB container → API container → reverse-proxy container
- ML pipeline: GPU node → model server → request handler

This ordering is critical for binary search and for startup sequencing —
restart the database before the API.

### 1.3 Check for Existing Heal Scripts

```bash
ls -la debug/ 2>/dev/null
```

If an existing monolithic `check.py`, `debug.py`, or `heal.py` exists, read
it to:
- Extract reusable helper functions (HTTP, Docker, color output)
- Map existing infrastructure checks to their target services
- Preserve any healing logic that already works (restart sequences, rebuild
  triggers, config-drift fixes)

If you find functional/business-logic tests in those scripts, **do not
preserve them in the heal framework** — note them and recommend moving them
to QA. Heal stays infrastructure-only.

---

## Phase 2: Generate Framework

### 2.1 Directory Structure

Create this structure in `debug/`:

```
debug/
├── heal.py                   # Master orchestrator — entry point
├── _common.py                # Shared infrastructure helpers
├── test_connectivity.py      # Infrastructure smoke test (can data flow?)
├── test_<service1>.py        # Per-service infrastructure check+heal
├── test_<service2>.py        # Per-service infrastructure check+heal
└── ...
```

### 2.2 `_common.py` — Shared Infrastructure Helpers

```python
#!/usr/bin/env python3
"""Shared helpers for infrastructure heal scripts."""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

# ── CLI flags ─────────────────────────────────────────────────────────────────
HEAL = "--debugonly" not in sys.argv  # heal by default, --debugonly skips fixes

# ── Colors ────────────────────────────────────────────────────────────────────
# Never red on black — unreadable on dark terminals. Use bright magenta for
# errors, yellow for warnings.
GREEN   = "\033[92m"
YELLOW  = "\033[93m"
MAGENTA = "\033[95m"
CYAN    = "\033[96m"
BOLD    = "\033[1m"
RESET   = "\033[0m"

def ok(msg):      print(f"  {GREEN}✓{RESET} {msg}")
def warn(msg):    print(f"  {YELLOW}⚠{RESET} {msg}")
def fail(msg):    print(f"  {MAGENTA}✗{RESET} {msg}")
def header(msg):  print(f"\n{BOLD}{msg}{RESET}")
def healing(msg): print(f"  {CYAN}⚕{RESET} {BOLD}HEAL:{RESET} {msg}")

# ── HTTP helpers (for connectivity checks only, not response validation) ──────
def get(url, timeout=5):
    """Fetch a URL. Returns (status_code, body) or (None, error_str).
    Used for liveness/readiness probes — NOT for asserting response content."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return None, str(e)

# ── Docker helpers ────────────────────────────────────────────────────────────
def compose_cmd(compose_file="docker-compose.yml"):
    """Return the base docker compose command."""
    return ["docker", "compose", "-f", compose_file]

def compose_up(service, compose_file="docker-compose.yml"):
    """Start a service via docker compose."""
    healing(f"Starting {service}...")
    subprocess.run([*compose_cmd(compose_file), "up", "-d", service],
                   capture_output=True)

def compose_restart(service, compose_file="docker-compose.yml", wait=5):
    """Restart a service and wait for it to stabilize."""
    healing(f"Restarting {service}...")
    subprocess.run([*compose_cmd(compose_file), "restart", service],
                   capture_output=True)
    import time
    time.sleep(wait)

def compose_build(service, compose_file="docker-compose.yml"):
    """Rebuild a service image. Use when config or deps changed."""
    healing(f"Rebuilding {service}...")
    subprocess.run([*compose_cmd(compose_file), "build", service],
                   capture_output=True)

def docker_ps():
    """Return docker ps output as a list of dicts."""
    result = subprocess.run(
        ["docker", "ps", "--format", "{{json .}}"],
        capture_output=True, text=True
    )
    containers = []
    for line in result.stdout.strip().split("\n"):
        if line.strip():
            containers.append(json.loads(line))
    return containers

def container_running(name):
    """Check if a container is running by name substring."""
    for c in docker_ps():
        if name in c.get("Names", ""):
            return "Up" in c.get("Status", "")
    return False

def tail_logs(service, lines=20, compose_file="docker-compose.yml"):
    """Return recent logs for a service. For diagnostics, not assertions."""
    result = subprocess.run(
        [*compose_cmd(compose_file), "logs", "--tail", str(lines), service],
        capture_output=True, text=True
    )
    return result.stdout + result.stderr

# ── Port/network helpers ──────────────────────────────────────────────────────
def port_open(host, port, timeout=2):
    """Check if a TCP port accepts connections. Infrastructure only."""
    import socket
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False

# ── Result helpers ────────────────────────────────────────────────────────────
def result_pass(msg=""):
    return {"status": "pass", "error": None, "msg": msg}

def result_fail(error, healed=False):
    return {"status": "fail", "error": error, "healed": healed}
```

### 2.3 Per-Service Infrastructure Script Contract

Every `test_<service>.py` MUST implement this contract. **Infrastructure
checks only.** No assertions about response content, business logic, or
functional behavior.

```python
#!/usr/bin/env python3
"""Infrastructure check + heal for <Service Name>.

Scope: container up, port open, health endpoint reachable, config loadable.
NOT in scope: response content, business logic, functional correctness.
Functional tests live in tests/ and are run by /qa or iris-qa.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from _common import *

# ── Configuration ─────────────────────────────────────────────────────────────
SERVICE_NAME = "<docker-service-name>"
HEALTH_URL = "http://localhost:<port>/health"  # liveness/readiness only
PORT = <port>
COMPOSE_FILE = "<path-to-compose-file>"

# ── Check ─────────────────────────────────────────────────────────────────────
def test():
    """Diagnose infrastructure for this service. Returns result dict.

    Checks (in order):
    1. Container running?
    2. Port accepting connections?
    3. Health endpoint returning 200?

    Does NOT check: response content, business logic, data correctness.
    """
    header(f"Infrastructure check: {SERVICE_NAME}")

    # 1. Container running
    if not container_running(SERVICE_NAME):
        fail(f"{SERVICE_NAME} container not running")
        return result_fail(f"{SERVICE_NAME} not running")
    ok(f"{SERVICE_NAME} container running")

    # 2. Port reachable
    if not port_open("localhost", PORT):
        fail(f"{SERVICE_NAME} port {PORT} not accepting connections")
        return result_fail(f"port {PORT} closed")
    ok(f"port {PORT} open")

    # 3. Health endpoint reachable (status only — not body content)
    status, _ = get(HEALTH_URL)
    if status != 200:
        fail(f"{SERVICE_NAME} health endpoint returned {status}")
        return result_fail(f"health endpoint {status}")
    ok(f"health endpoint OK")

    return result_pass()

# ── Heal ──────────────────────────────────────────────────────────────────────
def heal():
    """Diagnose + fix infrastructure issues. Returns result dict."""
    result = test()
    if result["status"] == "pass":
        return result

    error = result["error"]

    # Infrastructure fixes only
    if "not running" in error:
        if not HEAL:
            return result
        compose_up(SERVICE_NAME, COMPOSE_FILE)
        return test()

    if "port" in error or "health endpoint" in error:
        if not HEAL:
            return result
        compose_restart(SERVICE_NAME, COMPOSE_FILE)
        return test()

    # Service-specific infrastructure fixes (config drift, GPU memory,
    # disk space, image rebuild). NOT application bugs — those go to coders.

    return result_fail(error, healed=False)

# ── CLI ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    result = heal()
    sys.exit(0 if result["status"] == "pass" else 1)
```

**Key rules for each service script:**
- `test()` only diagnoses infrastructure — never modifies state, never asserts content
- `heal()` calls `test()` first, then applies infrastructure fixes if `HEAL` is True
- After each fix attempt, re-run `test()` to verify
- Return structured results for the master orchestrator
- Each script is importable AND standalone

### 2.4 `test_connectivity.py` — Infrastructure Smoke Test

The connectivity smoke test verifies that the **wires are connected** — data
can flow through the infrastructure. It does NOT verify that the data is
correct.

```python
"""Infrastructure connectivity smoke test.

Verifies: services can talk to each other, ports are reachable,
auth handshakes succeed, network paths are open.

Does NOT verify: response content, business logic, data correctness.
That's QA's job (see tests/ or run /qa).
"""
```

Design the smoke test to:
1. Hit the entry-point service's health endpoint
2. Confirm it can reach its dependencies (e.g., API can reach DB,
   orchestrator can reach worker)
3. Verify auth handshakes complete (e.g., bearer token accepted)
4. Complete within a few seconds (it's a smoke test, not a load test)

**What this test asks:** "Is everything wired up?"
**What this test does NOT ask:** "Does it produce the right output?"

If the smoke test passes but the application is buggy, that's QA's signal —
not heal's. Heal's job is done when the wires are connected.

### 2.5 `heal.py` — Master Orchestrator

Master orchestrator implements **binary-search fault isolation** for
infrastructure problems:

```python
#!/usr/bin/env python3
"""
Master infrastructure heal orchestrator.
Strategy: connectivity smoke test → binary search on failure → targeted heal.

Usage:
    python debug/heal.py              # Full heal (default)
    python debug/heal.py --debugonly  # Diagnose only, no fixes
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from _common import *

# Import all service test modules
import test_connectivity
# Import service modules in dependency order
import test_<first>
import test_<second>
# ... etc

# ── Service Pipeline ──────────────────────────────────────────────────────────

# Ordered list of (name, module) tuples — dependency order for binary search
PIPELINE = [
    ("service1", test_service1),
    ("service2", test_service2),
    # ...
]

# ── Binary Search ────────────────────────────────────────────────────────────

def binary_search_fault(services):
    """Recursively halve the service list to isolate the broken service."""
    if len(services) == 1:
        name, mod = services[0]
        header(f"Isolated infrastructure fault: {name}")
        return mod.heal()

    mid = len(services) // 2
    first_half = services[:mid]
    second_half = services[mid:]

    header(f"Checking first half: {[c[0] for c in first_half]}")
    for name, mod in first_half:
        result = mod.test()
        if result["status"] == "fail":
            header(f"Fault in first half — narrowing")
            return binary_search_fault(first_half)

    header(f"First half OK — fault must be in second half")
    return binary_search_fault(second_half)

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    header("Infrastructure Heal Framework")
    print(f"  Mode: {'HEAL' if HEAL else 'DIAGNOSE ONLY'}")
    print()

    # Step 1: Connectivity smoke test
    header("Step 1: Connectivity smoke test")
    smoke_result = test_connectivity.test()

    if smoke_result["status"] == "pass":
        ok("Infrastructure connectivity OK — all services reachable")
        print(f"\n{GREEN}{BOLD}Infrastructure operational.{RESET}")
        print(f"{YELLOW}Note: this verifies infrastructure only. Run /qa to verify application correctness.{RESET}")
        return 0

    fail(f"Connectivity smoke test failed: {smoke_result['error']}")

    # Step 2: Binary search to isolate the broken service
    header("Step 2: Binary search infrastructure fault isolation")
    fault_result = binary_search_fault(PIPELINE)

    if fault_result["status"] == "pass":
        ok("Service healed — re-running smoke test")
        # Step 3: Verify the fix
        header("Step 3: Verification")
        verify = test_connectivity.test()
        if verify["status"] == "pass":
            print(f"\n{GREEN}{BOLD}Infrastructure operational after heal.{RESET}")
            return 0
        else:
            fail(f"Smoke test still failing: {verify['error']}")
            return 1
    else:
        fail(f"Could not heal: {fault_result['error']}")
        if not fault_result.get("healed"):
            print(f"\n{MAGENTA}Manual intervention required.{RESET}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

---

## Phase 3: Customize for Project

After generating the framework scaffold:

1. **Read each service's existing health check** from the compose file
2. **Write per-service infrastructure checks** — these are the standard
   infrastructure dimensions:
   - Container running (`docker ps`)
   - Port reachable (TCP connect)
   - Health endpoint returns 200 (status only, not body content)
   - Required env vars present (read from `docker inspect`)
   - Required volumes mounted
   - Required network reachable (e.g., can the API container resolve the DB
     container's hostname?)
   - For GPU services: GPU available, memory not exhausted
   - For DB services: connection accepted (`SELECT 1`, not row content)
3. **Write per-service infrastructure heal logic** — common fixes:
   - Container not running → `compose_up`
   - Container unhealthy → `compose_restart`
   - GPU memory exhaustion → unload models, restart container
   - Port conflict → identify and kill conflicting process
   - Config drift → re-apply known-good config (re-mount, re-render)
   - Image stale (deps changed) → `compose_build` then `compose_restart`
   - DB connection rejected → check credentials, restart DB
4. **Write the connectivity smoke test** — what's the minimal set of calls
   that proves the wires are connected?

**Boundary check:** If you find yourself writing a check that asserts what
the application returns (specific values, business logic, data shape), stop.
That's a functional test — it belongs in `tests/`, run by `/qa` or
`iris-qa`. Heal stops at "is the response 200?" — QA owns "is the response
correct?"

---

## Phase 4: Verify

Run the framework:

```bash
python debug/heal.py              # Full heal
python debug/heal.py --debugonly  # Diagnose only
python debug/test_<service>.py    # Single service
```

Verify:
- Each service script runs standalone
- Master orchestrator correctly identifies healthy vs unhealthy services
- Binary search isolates faults to the correct service
- Healing fixes actually work (re-test after heal)

---

## Important Rules

- **Infrastructure only.** /heal does not write application code, business
  logic, or functional tests. If a check asserts response content or business
  behavior, it doesn't belong here. Move it to `/qa` or `/unit-test-builder`.
- **Connectivity first, always.** If the smoke test passes, no per-service
  checks are needed. This saves significant time.
- **Binary search, not linear scan.** For N services, binary search finds the
  fault in O(log N) checks instead of O(N).
- **Heal by default, `--debugonly` to skip.** The user wants infrastructure
  fixed, not just diagnosed.
- **Re-test after every heal.** Never assume a fix worked — verify it.
- **Structured results.** Every test/heal returns
  `{"status": "pass"|"fail", "error": str, "healed": bool}` so the
  orchestrator can make decisions.
- **No external dependencies.** Heal scripts use only stdlib (`urllib`,
  `subprocess`, `socket`, `json`). They must work even when the project's
  application dependencies are broken.
- **Preserve existing healing logic.** If the project already has working
  infrastructure fixes in `check.py`, extract and reuse them. Don't reinvent.
  But do NOT preserve functional/business-logic tests — flag them for QA.
- **All infrastructure diagnostics go INTO the framework.** When you need a
  new diagnostic to understand a failure, do NOT run ad-hoc terminal
  commands. Add it as a new check inside the appropriate `test_<service>.py`
  and re-run heal.py. Every diagnostic insight must be captured.
- **All infrastructure fixes go INTO the framework.** When you identify a
  remedial action, do NOT run it as a one-off. Add it as a heal step in the
  appropriate `test_<service>.py` and re-run heal.py to verify. Every fix
  must be repeatable so heal.py can apply it autonomously next time.
- **Rebuilds are a valid heal action.** If a fix requires
  `docker compose build <service>` followed by `compose_restart`, add that as
  a heal step. Don't shy away from rebuilds.
- **Hand-off to QA.** When heal.py reports "infrastructure operational" but
  the user reports the app is buggy, the next step is `/qa`, not /heal. Heal
  has done its job when the wires are connected.
