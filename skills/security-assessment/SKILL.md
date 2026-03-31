---
name: security-assessment
description: >
  Security assessment for MCP servers and web applications. Checks for information
  disclosure (CWE-200), excessive data exposure, verbose errors, internal path leaks,
  and other OWASP vulnerabilities through MCP tool interfaces. Trigger on: "security
  check", "security assessment", "audit MCP", "check for leaks", "CWE-200", "information
  disclosure", or before shipping any MCP server to production.
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

# Security Assessment

## Purpose

Systematically audit MCP servers and web applications for security vulnerabilities,
starting with the most common and damaging: information disclosure through tool
responses, error messages, and API surfaces.

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

---

## Phase 1: Discovery

### 1.1 Identify the MCP server

Find the MCP server code:

```bash
find . -name "mcp_server.py" -o -name "mcp*.py" -o -name "server.py" | head -20
```

```bash
grep -rl "@mcp.tool\|@server.list_tools\|@server.call_tool" --include="*.py" . | head -20
```

Read each file to build a complete list of:
- All MCP tools (name, parameters, return types)
- All error handling paths
- All data returned to the client
- All imports and dependencies

### 1.2 Identify the web endpoints

```bash
grep -rn "@app.get\|@app.post\|@app.put\|@app.delete\|@router" --include="*.py" . | head -30
```

Map all HTTP endpoints alongside the MCP tools.

### 1.3 Identify configuration and secrets handling

```bash
find . -name ".env*" -o -name "config.py" -o -name "config.json" -o -name "settings.py" | head -20
```

```bash
grep -rn "os.environ\|os.getenv\|API_KEY\|SECRET\|TOKEN\|PASSWORD\|CREDENTIAL" --include="*.py" . | head -30
```

---

## Phase 2: CWE-200 — Information Disclosure

This is the primary assessment. MCP tools return data directly to AI agents,
and agents include that data in their context. Any internal information in tool
responses becomes visible to the user and potentially to other agents.

### 2.1 Excessive data in tool responses

For each MCP tool, check what it returns:

**Stack traces and internal errors:**
- Does any tool return raw exception messages with file paths, line numbers, or stack traces?
- Are Python tracebacks ever included in error responses?
- Do error messages reveal internal class names, function names, or module paths?

```bash
grep -n "traceback\|str(e)\|repr(e)\|format_exc\|exc_info" --include="*.py" -r . | head -20
```

**Internal file paths:**
- Do responses include absolute server paths (`/app/`, `/home/`, `/data/`)?
- Are file paths from the container leaked in error messages or metadata?

```bash
grep -n '"/app/\|"/home/\|"/data/\|"/tmp/\|os.path\|__file__' --include="*.py" -r . | head -20
```

**Database internals:**
- Are database IDs, internal primary keys, or auto-increment values exposed?
- Are SQL queries or database error messages returned to clients?

```bash
grep -n "sqlite\|SELECT\|INSERT\|UPDATE\|DELETE\|\.execute(" --include="*.py" -r . | head -20
```

**Configuration and environment:**
- Are environment variable values included in responses?
- Are config file contents returned to the client?
- Do debug/diagnostic tools expose internal settings?

```bash
grep -n "os.environ\[.*\]\|os.getenv(" --include="*.py" -r . | head -20
```

**Verbose metadata:**
- Do list/read tools return internal fields that clients don't need?
- Are timestamps in internal format (epoch) instead of human-readable?
- Are internal state flags (dirty, synced, cached) leaked?

### 2.2 Error handling audit

For every try/except block in the MCP server:

**Check:** Does the except clause return the raw exception to the client?

```python
# VULNERABLE — leaks internal details
except Exception as e:
    return f"Error: {e}"  # Could contain file paths, SQL, credentials

# SAFE — generic message, details logged server-side
except Exception as e:
    log.error("Operation failed: %s", e)
    return "Operation failed. Check server logs for details."
```

```bash
grep -n "except.*:\s*$" --include="*.py" -A3 -r . | grep -i "return.*str(e)\|return.*repr\|return.*Error.*{e}" | head -20
```

### 2.3 Health and diagnostic endpoints

Check what `/health` and any debug endpoints return:

- `/health` should return ONLY `{"status": "ok", "service": "<name>"}` — no version,
  no uptime, no dependency status, no internal IPs
- No `/debug`, `/status`, `/info`, `/metrics` endpoints should exist in production
- No Swagger/OpenAPI docs served in production unless intended

```bash
grep -n "/health\|/debug\|/status\|/info\|/metrics\|/docs\|/openapi" --include="*.py" -r . | head -20
```

### 2.4 Response field audit

For each MCP tool that returns data, build a field inventory:

| Tool | Field | Contains | Exposure Risk |
|------|-------|----------|--------------|
| spec_read | id | Internal hierarchy ID | Low — by design |
| spec_read | _internal_state | Sync flag | HIGH — internal |
| audit_log | stack_trace | Python traceback | CRITICAL — CWE-200 |

Flag any field where:
- The field name starts with `_` (internal convention)
- The value contains file paths, IP addresses, or hostnames
- The value contains credentials, tokens, or keys
- The field is not documented in the tool's schema

---

## Phase 3: Additional CWE Checks

### 3.1 CWE-209 — Error Messages Containing Sensitive Information

Specifically check that error messages do not contain:
- Database connection strings
- API keys or tokens (even partial)
- User credentials
- Internal IP addresses or hostnames
- File system paths beyond the application root

### 3.2 CWE-532 — Insertion of Sensitive Information into Log Files

Check that logging does not write:
- Full request/response bodies (may contain credentials)
- User passwords or tokens
- Full exception chains with credentials in the call stack

```bash
grep -n "log\.\(info\|debug\|warning\|error\).*password\|log\.\(info\|debug\|warning\|error\).*token\|log\.\(info\|debug\|warning\|error\).*key\|log\.\(info\|debug\|warning\|error\).*secret" --include="*.py" -ri . | head -20
```

### 3.3 CWE-22 — Path Traversal

Check any tool that accepts file paths:
- Is the path validated against a root directory?
- Can `../` escape the intended directory?
- Are symlinks followed outside the boundary?

```bash
grep -n "open(\|Path(\|os.path.join\|read_text\|write_text" --include="*.py" -r . | head -20
```

### 3.4 CWE-78 — OS Command Injection

Check any tool that runs shell commands:
- Is user input passed to `subprocess`, `os.system`, or `os.popen`?
- Is string formatting used to build shell commands?

```bash
grep -n "subprocess\|os.system\|os.popen\|shell=True" --include="*.py" -r . | head -20
```

### 3.5 CWE-918 — Server-Side Request Forgery (SSRF)

Check any tool that makes HTTP requests with user-supplied URLs:
- Can the URL point to internal services (localhost, 169.254.169.254)?
- Is the URL validated against an allowlist?

```bash
grep -n "httpx\.\|requests\.\|urllib\.\|urlopen\|aiohttp" --include="*.py" -r . | head -20
```

---

## Phase 4: Report

Generate a structured security report at `{repo}/jjstack/security-assessment.md`:

```markdown
# Security Assessment — {project name}

**Date:** {date}
**Scope:** MCP server + web endpoints
**Assessor:** Claude Code + jjstack /security-assessment

## Summary

- **Critical:** {count} findings
- **High:** {count} findings
- **Medium:** {count} findings
- **Low:** {count} findings

## Findings

### FINDING-001: {title}
- **Severity:** Critical / High / Medium / Low
- **CWE:** CWE-{number} — {name}
- **Location:** {file}:{line}
- **Description:** {what's wrong}
- **Evidence:** {code snippet or response showing the leak}
- **Remediation:** {specific fix}

### FINDING-002: ...
```

---

## Phase 5: Fix

For each finding, apply the fix:

1. **Critical and High:** Fix immediately using the Edit tool. These are active
   information leaks.
2. **Medium:** Fix in this session if time permits.
3. **Low:** Document in the report for later.

After fixing, re-run the relevant grep checks to verify the fix works.

All fixes go into the codebase, not run as one-off patches. The fix must be
permanent and survive container rebuilds.

---

## Important Rules

- **MCP tools are the primary attack surface.** Every tool response is visible to the
  user and potentially to other agents. Treat tool output like a public API response.
- **Error messages are information leaks.** Generic client-facing errors, detailed
  server-side logs. Never both in the same place.
- **Internal fields must not leak.** If a field starts with `_` or contains system
  metadata, it should not appear in MCP tool responses.
- **File paths are fingerprints.** Absolute paths reveal OS, username, directory
  structure, and deployment layout. Never return them to clients.
- **Health endpoints are minimal.** `{"status": "ok"}` is enough. Version numbers,
  dependency lists, and uptime are reconnaissance data.
- **Log what you need, not everything.** Full request/response logging is a liability
  when requests contain credentials.
