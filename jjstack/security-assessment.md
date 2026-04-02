# Security Assessment — jjstack

**Date:** 2026-03-30
**Scope:** Shell scripts (hooks, setup, bin), skill definitions
**Assessor:** Claude Code + jjstack /security-assessment

## Summary

- **Critical:** 0 findings
- **High:** 2 findings
- **Medium:** 3 findings
- **Low:** 2 findings

## Findings

### FINDING-001: Setup script overwrites existing permission hooks
- **Severity:** High
- **CWE:** CWE-276 — Incorrect Default Permissions
- **Location:** `setup:172`
- **Description:** The setup script uses `jq '.hooks.PermissionRequest = [...]'` which replaces ALL existing PermissionRequest hooks, not just adds jjstack's hook. If the user had custom permission hooks configured, they are silently destroyed. The same issue affects `PostToolUseFailure` at line 189.
- **Evidence:**
  ```bash
  jq '.hooks.PermissionRequest = [{"matcher": "", "hooks": [{"type": "command", "command": "~/.claude/hooks/auto-approve-safe.sh"}]}]' "$SETTINGS_FILE" > "$TMP_SETTINGS"
  ```
- **Remediation:** Use `jq '.hooks.PermissionRequest += [...]'` or check for existing entries and append. Better: read existing hooks, check if jjstack's hook is already present, and only add if missing.
- **Status:** FIXED — setup now appends to existing hooks array instead of replacing it.

### FINDING-002: Shell commands sent to external API for risk rating
- **Severity:** High
- **CWE:** CWE-319 — Cleartext Transmission of Sensitive Information
- **Location:** `hooks/auto-approve-safe.sh:57-74`
- **Description:** Every Bash command that Claude attempts to run is sent to the Anthropic API for risk rating. If a command contains embedded secrets (e.g., `curl -H "Authorization: Bearer sk-..."` or `export DB_PASSWORD=...`), those secrets are transmitted to the API. While the Anthropic API uses HTTPS, the command content becomes part of API logs and model context.
- **Evidence:**
  ```bash
  PAYLOAD=$(jq -n --arg cmd "$COMMAND" '{
    model: "claude-haiku-4-5-20251001",
    ...
    messages: [{role: "user", content: ("Rate the risk...\n\n" + $cmd)}]
  }')
  ```
- **Remediation:** Sanitize the command before sending: strip quoted strings, redact values after `=` in variable assignments, replace anything matching token/key/password patterns with `[REDACTED]`. Alternatively, expand the local heuristic to avoid API calls for commands containing potential secrets.
- **Status:** NOT FIXED — requires design decision on sanitization approach. Note: the commands are already visible to Anthropic via the Claude Code session itself, which somewhat mitigates this finding.

### FINDING-003: Weak fallback heuristic in auto-approve hook
- **Severity:** Medium
- **CWE:** CWE-183 — Permissive List of Allowed Inputs
- **Location:** `hooks/auto-approve-safe.sh:52,87`
- **Description:** When the API is unavailable, the fallback heuristic only blocks 5 patterns: `rm -rf`, `sudo`, `git push`, `git reset --hard`, `git clean`. Many dangerous operations pass through: `chmod 777`, `dd`, `mkfs`, `kill -9`, `docker rm -f`, `kubectl delete`, `DROP TABLE`, `curl | sh`, `> /dev/sda`, `:(){ :|:& };:` (fork bomb).
- **Evidence:**
  ```bash
  echo "$COMMAND" | grep -qE "rm -rf|sudo|git push|git reset --hard|git clean" && defer
  allow
  ```
- **Remediation:** Expand the pattern list to cover common destructive operations. Consider defaulting to `defer` (ask the user) instead of `allow` when the API is unavailable — fail-closed rather than fail-open.
- **Status:** FIXED — fallback now uses a safe-allowlist approach (fail-closed). Only known read-only commands are auto-approved; everything else defers to the user.

### FINDING-004: Dependency cloned without integrity verification
- **Severity:** Medium
- **CWE:** CWE-494 — Download of Code Without Integrity Check
- **Location:** `setup:38`
- **Description:** gstack is cloned from GitHub and its `setup` script is executed immediately, with no verification of commit hash, tag signature, or content integrity. A compromised GitHub account or MITM on HTTPS could deliver malicious code.
- **Evidence:**
  ```bash
  git clone https://github.com/garrytan/gstack.git "$GSTACK_DIR"
  ...
  (cd "$GSTACK_DIR" && ./setup)
  ```
- **Remediation:** Pin to a specific commit hash or tag. Verify GPG signature on the tag. At minimum, verify the VERSION file matches expected content before running setup.

### FINDING-005: Uninstaller deletes all PermissionRequest hooks
- **Severity:** Medium
- **CWE:** CWE-276 — Incorrect Default Permissions
- **Location:** `uninstall:87`
- **Description:** The uninstaller runs `jq 'del(.hooks.PermissionRequest)'` which removes ALL PermissionRequest hooks, not just the jjstack one. This silently removes any hooks that were added after jjstack install.
- **Evidence:**
  ```bash
  jq 'del(.hooks.PermissionRequest)' "$SETTINGS_FILE" > "$TMP_SETTINGS"
  ```
- **Remediation:** Filter only the jjstack-specific hook entry from the array instead of deleting the entire key.
- **Status:** FIXED — uninstaller now filters only jjstack-specific hook entries, preserving other hooks.

### FINDING-006: MCP reconnect hook suppresses errors from user
- **Severity:** Low
- **CWE:** CWE-223 — Omission of Security-relevant Information
- **Location:** `hooks/mcp-reconnect.sh:61`
- **Description:** The hook instructs Claude to reconnect MCP servers "silently" without informing the user. Up to 3 reconnection attempts happen invisibly. A persistently failing MCP server could indicate a security issue (compromised server, network attack) that the user should be aware of.
- **Evidence:**
  ```
  "Do NOT ask the user about this — just reconnect and retry silently."
  ```
- **Remediation:** Remove the "silently" instruction. Allow Claude to briefly mention the reconnection attempt so the user has visibility.

### FINDING-007: Predictable temp file path for retry counter
- **Severity:** Low
- **CWE:** CWE-377 — Insecure Temporary File
- **Location:** `hooks/mcp-reconnect.sh:36`
- **Description:** The retry counter uses a predictable path `/tmp/jjstack-mcp-reconnect-{server}.count`. Another user on the same system could manipulate the counter file to either suppress reconnection attempts (write a high number) or force infinite retries (keep resetting to 0). Low risk on single-user systems.
- **Evidence:**
  ```bash
  COUNTER_FILE="/tmp/jjstack-mcp-reconnect-${SERVER_NAME}.count"
  ```
- **Remediation:** Use `mktemp` with a user-specific directory, or place the counter under `~/.jjstack/` instead of `/tmp/`.
- **Status:** FIXED — counter file moved to `~/.jjstack/`.
