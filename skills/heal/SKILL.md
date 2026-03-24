---
name: heal
description: |
  Generate modular debug/heal frameworks for containerized projects. Discovers
  docker-compose services, creates per-component test+heal scripts, and a master
  orchestrator with binary-search fault isolation. Use when asked to "create debug
  scripts", "heal framework", "make it self-healing", or "debug setup".
  Proactively suggest when a project has containers but no modular debug scripts.
---

# Modular Debug/Heal Framework Generator

## Overview

This skill generates a self-healing debug framework for any containerized project. It creates:
- Per-component test+heal scripts that can run standalone or be orchestrated
- A master `heal.py` that uses binary-search fault isolation to minimize debugging time
- An end-to-end test that exercises the full pipeline before testing individual components

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

### 1.2 Identify Pipeline Order

Determine the data flow through the services. For example:
- Voice AI: WAV → STT → LLM → Tools → TTS → Audio
- Web app: Request → API → Database → Response
- ML pipeline: Data → Preprocessing → Model → Postprocessing

This ordering is critical for binary search — the master `heal.py` needs to know which half of the pipeline to test first.

### 1.3 Check for Existing Debug Scripts

```bash
ls -la debug/ 2>/dev/null
```

If an existing monolithic `check.py` or `debug.py` exists, read it to:
- Extract reusable helper functions (HTTP helpers, Docker helpers, color output)
- Map existing check functions to their target components
- Preserve any healing logic that already works

---

## Phase 2: Generate Framework

### 2.1 Directory Structure

Create this structure in `debug/`:

```
debug/
├── heal.py              # Master orchestrator — entry point
├── _common.py           # Shared helpers
├── test_e2e.py          # End-to-end pipeline test
├── test_<service1>.py   # Per-service test+heal
├── test_<service2>.py   # Per-service test+heal
└── ...
```

### 2.2 `_common.py` — Shared Helpers

Every debug framework needs these helpers. Extract from existing code or generate:

```python
#!/usr/bin/env python3
"""Shared helpers for debug/heal scripts."""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

# ── CLI flags ─────────────────────────────────────────────────────────────────
HEAL = "--debugonly" not in sys.argv  # heal by default, --debugonly skips fixes

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg):      print(f"  {GREEN}✓{RESET} {msg}")
def warn(msg):    print(f"  {YELLOW}⚠{RESET} {msg}")
def fail(msg):    print(f"  {RED}✗{RESET} {msg}")
def header(msg):  print(f"\n{BOLD}{msg}{RESET}")
def healing(msg): print(f"  {CYAN}⚕{RESET} {BOLD}HEAL:{RESET} {msg}")

# ── HTTP helpers ──────────────────────────────────────────────────────────────
def get(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return None, str(e)

def post_json(url, data, timeout=30):
    body = json.dumps(data).encode()
    req = urllib.request.Request(url, data=body,
                                headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
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
    """Return recent logs for a service."""
    result = subprocess.run(
        [*compose_cmd(compose_file), "logs", "--tail", str(lines), service],
        capture_output=True, text=True
    )
    return result.stdout + result.stderr

# ── Result helpers ────────────────────────────────────────────────────────────
def result_pass(msg=""):
    return {"status": "pass", "error": None, "msg": msg}

def result_fail(error, healed=False):
    return {"status": "fail", "error": error, "healed": healed}
```

### 2.3 Per-Component Script Contract

Every `test_<component>.py` MUST implement this contract:

```python
#!/usr/bin/env python3
"""Test + heal script for <Component Name>."""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from _common import *

# ── Configuration ─────────────────────────────────────────────────────────────
SERVICE_NAME = "<docker-service-name>"
HEALTH_URL = "http://localhost:<port>/health"  # or appropriate endpoint
COMPOSE_FILE = "<path-to-compose-file>"

# ── Test ──────────────────────────────────────────────────────────────────────
def test():
    """Diagnose this component. Returns result dict."""
    header(f"Testing {SERVICE_NAME}")

    # 1. Check container is running
    if not container_running(SERVICE_NAME):
        fail(f"{SERVICE_NAME} container not running")
        return result_fail(f"{SERVICE_NAME} not running")
    ok(f"{SERVICE_NAME} container running")

    # 2. Check health endpoint
    status, body = get(HEALTH_URL)
    if status != 200:
        fail(f"{SERVICE_NAME} health check failed: {status}")
        return result_fail(f"Health check returned {status}")
    ok(f"{SERVICE_NAME} health OK")

    # 3. Functional test (component-specific)
    # ... send test data, verify output ...

    return result_pass()

# ── Heal ──────────────────────────────────────────────────────────────────────
def heal():
    """Diagnose + fix this component. Returns result dict."""
    result = test()
    if result["status"] == "pass":
        return result

    error = result["error"]

    # Attempt fixes based on error type
    if "not running" in error:
        if not HEAL:
            return result
        compose_up(SERVICE_NAME, COMPOSE_FILE)
        return test()  # re-test after fix

    if "Health check" in error:
        if not HEAL:
            return result
        compose_restart(SERVICE_NAME, COMPOSE_FILE)
        return test()  # re-test after fix

    # Component-specific healing logic here...

    return result_fail(error, healed=False)

# ── CLI ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    result = heal()
    sys.exit(0 if result["status"] == "pass" else 1)
```

**Key rules for each component script:**
- `test()` only diagnoses — never modifies state
- `heal()` calls `test()` first, then fixes if `HEAL` is True (i.e., `--debugonly` not passed)
- After each fix attempt, re-run `test()` to verify
- Return structured results for the master orchestrator
- Each script is importable AND standalone

### 2.4 `test_e2e.py` — End-to-End Pipeline Test

The e2e test exercises the FULL pipeline in a single request. If this passes, no component tests needed.

Design the e2e test to:
1. Send realistic input through the pipeline entry point
2. Verify output at the pipeline exit point
3. Check that intermediate steps actually executed (via logs or side effects)
4. Complete within a reasonable timeout (30-60 seconds)

**Example for a voice AI pipeline:**
- Submit a WAV file with a command that triggers tool use
- Verify: STT transcription → LLM response with tool call → tool execution → TTS audio output
- This tests every component without testing them individually

**Example for a web app:**
- Submit an API request that touches the database
- Verify: response is correct, database was updated, cache was invalidated

### 2.5 `heal.py` — Master Orchestrator

The master orchestrator implements **binary-search fault isolation**:

```python
#!/usr/bin/env python3
"""
Master debug/heal orchestrator.
Strategy: e2e test first → binary search on failure → targeted heal.

Usage:
    python debug/heal.py              # Full heal (default)
    python debug/heal.py --debugonly  # Diagnose only, no fixes
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from _common import *

# Import all component test modules
import test_e2e
# Import component modules in pipeline order
import test_<first>
import test_<second>
# ... etc

# ── Pipeline Definition ──────────────────────────────────────────────────────

# Ordered list of (name, module) tuples — pipeline order matters for binary search
PIPELINE = [
    ("component1", test_component1),
    ("component2", test_component2),
    # ...
]

# ── Binary Search ────────────────────────────────────────────────────────────

def binary_search_fault(components):
    """Recursively halve the pipeline to isolate the failing component."""
    if len(components) == 1:
        name, mod = components[0]
        header(f"Isolated fault: {name}")
        return mod.heal()

    mid = len(components) // 2
    first_half = components[:mid]
    second_half = components[mid:]

    header(f"Testing first half: {[c[0] for c in first_half]}")
    for name, mod in first_half:
        result = mod.test()
        if result["status"] == "fail":
            header(f"Fault in first half — narrowing to {[c[0] for c in first_half]}")
            return binary_search_fault(first_half)

    header(f"First half OK — fault must be in: {[c[0] for c in second_half]}")
    return binary_search_fault(second_half)

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    header("TARS Debug/Heal Framework")
    print(f"  Mode: {'HEAL' if HEAL else 'DEBUG ONLY'}")
    print()

    # Step 1: End-to-end test
    header("Step 1: End-to-end pipeline test")
    e2e_result = test_e2e.test()

    if e2e_result["status"] == "pass":
        ok("End-to-end test passed — all components healthy")
        print(f"\n{GREEN}{BOLD}All systems operational.{RESET}")
        return 0

    fail(f"End-to-end test failed: {e2e_result['error']}")

    # Step 2: Binary search to isolate fault
    header("Step 2: Binary search fault isolation")
    fault_result = binary_search_fault(PIPELINE)

    if fault_result["status"] == "pass":
        ok("Component healed — re-running e2e test")
        # Step 3: Verify the fix
        header("Step 3: Verification")
        verify = test_e2e.test()
        if verify["status"] == "pass":
            print(f"\n{GREEN}{BOLD}All systems operational after heal.{RESET}")
            return 0
        else:
            fail(f"E2E still failing after heal: {verify['error']}")
            return 1
    else:
        fail(f"Could not heal: {fault_result['error']}")
        if not fault_result.get("healed"):
            print(f"\n{RED}Manual intervention required.{RESET}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

---

## Phase 3: Customize for Project

After generating the framework scaffold:

1. **Read each component's existing health checks** from the compose file or existing debug scripts
2. **Write component-specific test logic** — not just "is it running" but functional verification:
   - STT: submit audio, verify transcription
   - LLM: submit prompt, verify response
   - TTS: submit text, verify audio output
   - Database: query, verify data
   - API: request, verify response
3. **Write component-specific heal logic** — common fixes:
   - Container not running → `compose_up`
   - Container unhealthy → `compose_restart`
   - GPU memory exhaustion → unload models, restart
   - Port conflict → identify and kill conflicting process
   - Config drift → re-apply known-good config
4. **Write the e2e test** — the most important test. It should exercise the full pipeline with realistic data.

---

## Phase 4: Verify

Run the framework:

```bash
python debug/heal.py           # Full heal
python debug/heal.py --debugonly  # Diagnose only
python debug/test_<component>.py  # Single component
```

Verify:
- Each component script runs standalone
- Master orchestrator correctly identifies healthy vs unhealthy components
- Binary search isolates faults to the correct component
- Healing fixes actually work (re-test after heal)

---

## Important Rules

- **E2E first, always.** If the e2e test passes, no component tests are needed. This saves significant time.
- **Binary search, not linear scan.** For N components, binary search finds the fault in O(log N) tests instead of O(N).
- **Heal by default, `--debugonly` to skip.** The user wants things fixed, not just diagnosed.
- **Re-test after every heal.** Never assume a fix worked — verify it.
- **Structured results.** Every test/heal returns `{"status": "pass"|"fail", "error": str, "healed": bool}` so the orchestrator can make decisions.
- **No external dependencies.** Debug scripts use only stdlib (`urllib`, `subprocess`, `json`). They must work even when the project's dependencies are broken.
- **Preserve existing healing logic.** If the project already has a `check.py` with working fixes, extract and reuse that logic — don't reinvent it.
- **All debugging goes INTO the framework.** When you need to run additional diagnostics to understand a failure reported by heal.py, do NOT run ad-hoc commands in the terminal. Instead, add those diagnostic checks as new test steps inside the appropriate `test_<component>.py` script, then re-run heal.py. Every debugging insight must be captured in the framework so it's available next time.
- **All fixes go INTO the framework.** When you identify a remedial action to fix an issue, do NOT run it as a one-off command. Instead, add it as a heal step inside the appropriate `test_<component>.py` script's `heal()` function, then re-run heal.py to verify. Every fix must be repeatable — if the problem recurs, heal.py should fix it automatically without human intervention.
