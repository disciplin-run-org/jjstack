---
name: security-review
version: 0.4.0
description: |
  Security review for codebases, MCP servers, and web applications. Combines
  Anthropic's official security-review methodology, Sentry's investigation-first
  approach with 17 vulnerability references, OWASP Top 10:2025 + Agentic AI
  security, and jjstack's MCP-specific CWE assessment. Saves findings to repo,
  iterates to 10/10, injects DNA.
  jjstack skill that enhances the built-in /security-review.
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

# jjstack security-review

Enhanced security review that layers three trusted sources with jjstack's own
MCP-focused assessment:

1. **Anthropic** — official security-review methodology (by-reference, auto-updated)
2. **Sentry** — investigation-first approach with 17 vulnerability references (by-reference, auto-updated)
3. **OWASP** — Top 10:2025, ASVS 5.0, Agentic AI security, 20 language guides (by-copy from agamm)
4. **jjstack** — MCP server CWE assessment, secret detection, config self-audit

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

---

## Phase 1: Configure

```bash
cat ~/.claude/skills/jjstack/jjstack.config.yaml
```

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null)/.jjstack.config.yaml" 2>/dev/null || echo "No project override"
```

Store: `MIN_SCORE`, `MAX_ITERATIONS`, `OUTPUT_DIR`, DNA paths. Create output dir. Load DNA.

```bash
mkdir -p {OUTPUT_DIR}
```

### Mode selection

Detect the review mode from the user's invocation or context:

| Mode | Scope | Phases to run |
|------|-------|---------------|
| **full** (default) | Diff review + full CWE assessment | All phases |
| **diff** | Only files changed since base branch | Phases 2-5 (diff only), 7-10. Skip Phase 6 deep assessment |
| **diff:BRANCH** | Only files changed vs specified branch | Same as `diff` but against the named branch |
| **focus:auth** | Deep dive on authentication and authorization | Phases 2-4, then Phase 6 scoped to auth/session/permission code only |
| **focus:secrets** | Deep dive on secrets and credentials | Phases 2-4, then Phase 6.3 (secret detection) + git history only |
| **focus:mcp** | Deep dive on MCP/agentic security | Phases 2-4, then Phase 6.2 (MCP assessment) only |
| **focus:supply-chain** | Deep dive on dependencies | Phases 2-4, then Phase 6.5 (supply chain) only |

Auto-detect mode from context:
- If invoked during a PR flow or the user says "review my changes" → `diff`
- If the user specifies a focus area → matching `focus:` mode
- Otherwise → `full`

---

## Phase 2: Load Anthropic security-review methodology

Read and internalize Anthropic's official security-review command. This defines
the core methodology: confidence scoring, false-positive filtering, exclusion
rules, and sub-task verification.

```bash
cat ~/.claude/skills/anthropic-security-review/.claude/commands/security-review.md 2>/dev/null || echo "Anthropic security-review not installed — using built-in methodology"
```

**From Anthropic, adopt unconditionally:**
- Confidence >= 0.8 threshold before reporting any finding
- All 17 hard exclusion rules (DoS, rate limiting, test files, log spoofing, etc.)
- All 12 precedent rules (UUIDs safe, env vars trusted, React auto-escapes, etc.)
- 3-phase analysis: context research, comparative analysis, vulnerability assessment
- Sub-task spawning for parallel false-positive verification
- The principle: "Better to miss theoretical issues than flood with false positives"

---

## Phase 3: Load Sentry investigation-first methodology

Read and internalize Sentry's security-review skill. This provides the
investigation-first approach and vulnerability reference library.

```bash
cat ~/.claude/skills/getsentry-skills/plugins/sentry-skills/skills/security-review/SKILL.md 2>/dev/null || echo "Sentry skills not installed — using built-in methodology"
```

**From Sentry, adopt:**
- "Do NOT report issues based solely on pattern matching. Investigate first."
- Trace data flow from source to sink before reporting
- Distinguish attacker-controlled vs. server-controlled values
- Framework-aware false-positive suppression

**Load Sentry reference files based on detected code type:**

| Code Type | Reference to load |
|-----------|-------------------|
| API endpoints, routes | `references/authorization.md`, `references/authentication.md`, `references/injection.md` |
| Frontend, templates | `references/xss.md`, `references/csrf.md` |
| File handling, uploads | `references/file-security.md` |
| Crypto, secrets, tokens | `references/cryptography.md`, `references/data-protection.md` |
| Data serialization | `references/deserialization.md` |
| External requests | `references/ssrf.md` |
| Business workflows | `references/business-logic.md` |
| GraphQL, REST design | `references/api-security.md` |
| Config, headers, CORS | `references/misconfiguration.md` |
| CI/CD, dependencies | `references/supply-chain.md` |
| Error handling | `references/error-handling.md` |
| Audit, logging | `references/logging.md` |
| Modern threats | `references/modern-threats.md` |

Reference path: `~/.claude/skills/getsentry-skills/plugins/sentry-skills/skills/security-review/`

**Load language guide** based on file extensions:
- `.py` → `languages/python.md`
- `.js`, `.ts` → `languages/javascript.md`
- `.go` → `languages/go.md`
- `.rs` → `languages/rust.md`
- `.java` → `languages/java.md`

**Load infrastructure guide** if applicable:
- `Dockerfile` → `infrastructure/docker.md`
- K8s manifests → `infrastructure/kubernetes.md`
- `.tf` files → `infrastructure/terraform.md`
- `.github/workflows/` → `infrastructure/ci-cd.md`
- AWS/GCP/Azure configs → `infrastructure/cloud.md`

---

## Phase 4: Load OWASP reference

```bash
cat ~/.claude/skills/jjstack/references/owasp-security/SKILL.md 2>/dev/null || echo "OWASP reference not installed"
```

**From OWASP, use:**
- OWASP Top 10:2025 as the systematic coverage checklist
- Language-specific security quirks for the detected language(s)
- Agentic AI Security (ASI01-ASI10) when reviewing MCP servers or agent systems
- ASVS 5.0 requirements when assessing authentication/session code
- Secure vs unsafe code pattern pairs for reviewer guidance

---

## Phase 5: Git diff security review

Review recent code changes for security vulnerabilities. Determine the best diff
range automatically:

```bash
git log --oneline -20
```

Pick the appropriate diff target:
- If a feature branch: diff against the base branch (`main` or `master`)
- If on main: diff the most recent commits
- If the user specified a range: use that

```bash
git diff {target}...HEAD
```

**Critical file detection** (from Pixelmojo): If the diff touches any of these
paths, auto-elevate review depth for those files — they deserve extra scrutiny:
- `**/auth/**`, `**/authentication/**`, `**/login/**`, `**/session/**`
- `**/payment/**`, `**/billing/**`, `**/checkout/**`
- `**/middleware/**`, `**/interceptor/**`
- `**/crypto/**`, `**/encryption/**`, `**/security/**`
- `**/permissions/**`, `**/rbac/**`, `**/acl/**`
- `**/.env*`, `**/config/secrets*`, `**/credentials*`

Apply the Anthropic methodology to the diff:
- Phase 1: Research repository context (security frameworks, existing patterns)
- Phase 2: Comparative analysis (deviations from established secure practices)
- Phase 3: Vulnerability assessment (trace data flow, check injection points)

Apply the Sentry methodology:
- For each potential finding, investigate the codebase to build confidence
- Trace data flow from source to sink
- Check if input is attacker-controlled or server-controlled
- Check for framework mitigations

**Only report findings with confidence >= 0.8.**

---

## Phase 6: Deep CWE assessment

Systematically audit the full codebase. This phase extends beyond the diff to
catch pre-existing vulnerabilities.

### 6.1 Discovery

Detect the project type and identify attack surfaces:

```bash
find . -name "mcp_server.py" -o -name "mcp*.py" -o -name "server.py" | head -20
```

```bash
grep -rl "@mcp.tool\|@server.list_tools\|@server.call_tool" --include="*.py" . | head -20
```

```bash
grep -rn "@app.get\|@app.post\|@app.put\|@app.delete\|@router" --include="*.py" . | head -30
```

```bash
find . -name ".env*" -o -name "config.py" -o -name "config.json" -o -name "settings.py" | head -20
```

```bash
find . -name "*.sh" -not -path "./.git/*" | head -20
```

### 6.2 MCP-specific assessment (jjstack original)

If MCP tools are detected, this is the primary attack surface:

**CWE-200 — Information Disclosure:**
- Stack traces and internal errors in tool responses
- Internal file paths leaked in error messages or metadata
- Database internals exposed (IDs, queries, error messages)
- Environment variable values in responses
- Internal fields (prefixed with `_`) in tool output

```bash
grep -n "traceback\|str(e)\|repr(e)\|format_exc\|exc_info" --include="*.py" -r . | head -20
```

```bash
grep -n '"/app/\|"/home/\|"/data/\|"/tmp/\|os.path\|__file__' --include="*.py" -r . | head -20
```

**Agentic AI / LLM risks (ASI01-ASI10 + afiqiqmal):**
- Prompt injection in MCP tool inputs (direct: user crafts malicious tool input; indirect: tool reads poisoned data that alters agent behavior)
- Tool permission escalation (tool grants more access than its description implies)
- MCP tool chaining attacks (tool A's output used to exploit tool B)
- Agent memory poisoning via tool responses (injecting instructions into conversation context)
- PII sent to external AI APIs without sanitization
- AI output rendered without sanitization (XSS via LLM response)
- Tool/function calling without permission checks or rate limits
- RAG data poisoning (corrupted retrieval data alters agent answers)
- Missing cost/abuse monitoring on AI API calls
- Fail-open when AI service is unavailable (fallback grants access instead of denying)
- CLAUDE.md / settings.json / .mcp.json configuration audit (hooks, permissions, MCP server configs)

**Health and diagnostic endpoints:**

```bash
grep -n "/health\|/debug\|/status\|/info\|/metrics\|/docs\|/openapi" --include="*.py" -r . | head -20
```

### 6.3 Secret detection

Scan for real secrets using format-specific regex patterns:

```bash
grep -rn "AKIA[0-9A-Z]\{16\}" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" --include="*.yaml" --include="*.yml" --include="*.json" . | head -10
```

```bash
grep -rn "ghp_[a-zA-Z0-9]\{36\}\|gho_[a-zA-Z0-9]\{36\}\|github_pat_" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" . | head -10
```

```bash
grep -rn "sk-[a-zA-Z0-9]\{20,\}\|sk-ant-" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" . | head -10
```

```bash
grep -rn "xoxb-\|xoxp-\|xoxa-\|xoxr-" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" . | head -10
```

```bash
grep -rn "BEGIN.*PRIVATE KEY" -r . --include="*.py" --include="*.js" --include="*.ts" --include="*.pem" --include="*.key" --include="*.env" | head -10
```

**Stripe, Twilio, SendGrid, database connection strings** (from CodyLunders):

```bash
grep -rn "sk_live_\|rk_live_" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" . | head -10
```

```bash
grep -rn "SK[a-f0-9]\{32\}" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" . | head -10
```

```bash
grep -rn "SG\.[a-zA-Z0-9_-]\{22\}\." --include="*.py" --include="*.js" --include="*.ts" --include="*.env" . | head -10
```

```bash
grep -rn "postgres://.*:.*@\|mongodb://.*:.*@\|mysql://.*:.*@\|redis://.*:.*@" --include="*.py" --include="*.js" --include="*.ts" --include="*.env" --include="*.yaml" --include="*.yml" . | head -10
```

**Git history scanning** — check for secrets in ALL commits, not just deleted files (from wshobson):

```bash
git log --all -p --diff-filter=D -- "*.env" "*.pem" "*.key" 2>/dev/null | head -50
```

```bash
git log -p --all -S 'password' --since="1 year ago" 2>/dev/null | head -30
```

```bash
git log -p --all -S 'api_key\|apikey\|secret_key\|access_key' --since="1 year ago" 2>/dev/null | head -30
```

### 6.4 Additional CWE checks

Run these checks using the Sentry reference files for context:

- **CWE-78 — OS Command Injection**
- **CWE-22 — Path Traversal**
- **CWE-918 — SSRF**
- **CWE-502 — Deserialization**
- **CWE-532 — Sensitive Info in Logs**
- **CWE-209 — Error Messages with Sensitive Info**

For each, apply the Anthropic exclusion rules and Sentry investigation methodology.
Only report with confidence >= 0.8.

### 6.5 Insecure defaults (from Trail of Bits)

Check for fail-open patterns where the app runs insecurely with missing config:

**Fallback secrets:** `env.get('SECRET') or 'default'` — app runs with weak secret
vs. **Fail-secure:** `env['SECRET']` — app crashes if missing

Scan for:
- Fallback secrets: `getenv.*or ['"]`, `process.env.* || ['"]`, `ENV.fetch.*default:`
- Debug mode defaults: `DEBUG.*=.*True`, `DEBUG.*=.*true`
- Permissive CORS: `CORS.*=.*\*`, `Access-Control-Allow-Origin: *`
- Default credentials: `password.*=.*['"][^'"]{8,}['"]` in non-test files
- Weak crypto defaults: `MD5|SHA1|DES|RC4|ECB` in security contexts

**Key distinction:** Only flag if the default is insecure AND the app runs with it.
Skip test fixtures, example files, and patterns where the app crashes without config.

### 6.6 Entry point analysis (from Trail of Bits)

Before deep review, systematically map all entry points to ensure complete coverage:

- All HTTP routes/endpoints (GET, POST, PUT, DELETE)
- All MCP tool handlers
- WebSocket endpoints
- CLI commands that accept external input
- Queue workers / webhook receivers
- Scheduled tasks that process external data

Classify each by access level: **Public** (unrestricted), **Authenticated** (requires login), **Admin** (requires privilege). Public entry points get highest scrutiny.

### 6.7 Supply chain risk (from Trail of Bits)

Check dependency health for red flags:

- **Single maintainer** — project maintained by one person (especially anonymous)
- **Unmaintained** — no updates for 12+ months, archived, or seeking new maintainers
- **Low popularity** — significantly fewer stars/downloads than alternatives
- **High-risk features** — FFI, deserialization, code execution
- **Missing security contact** — no SECURITY.md or security reporting process
- **Suspicious lifecycle scripts** — `preinstall`/`postinstall` in package.json that download or execute code

```bash
cat package.json 2>/dev/null | grep -A2 '"preinstall\|"postinstall\|"prepare"' | head -10
```

```bash
cat requirements.txt 2>/dev/null | head -20
```

```bash
cat go.mod 2>/dev/null | head -20
```

Flag dependencies that meet 2+ risk criteria. Don't flag vendored or well-known org-backed packages.

### 6.8 Cryptographic algorithm review (from alirezarezvani)

If the codebase uses cryptography, verify correct algorithm selection:

| Use case | Correct | Incorrect |
|----------|---------|-----------|
| Password hashing | Argon2id, bcrypt, scrypt | MD5, SHA1, SHA256 (unsalted) |
| Symmetric encryption | AES-256-GCM, ChaCha20-Poly1305 | DES, 3DES, RC4, AES-ECB |
| Asymmetric encryption | RSA-2048+, Ed25519, X25519 | RSA-1024, DSA |
| Signing | Ed25519, ECDSA (P-256), RSA-PSS | RSA-PKCS1v1.5 (for new code) |
| Hashing (non-password) | SHA-256, SHA-3, BLAKE2 | MD5, SHA1 |
| Random generation | `secrets` module, `crypto.randomBytes` | `random`, `Math.random()` |

```bash
grep -rn "md5\|sha1\|DES\|RC4\|ECB\|Math.random\|random.random" --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" -i . | head -20
```

Only flag weak crypto used for **security purposes** (passwords, tokens, encryption). MD5 for file checksums or cache keys is safe.

### 6.9 Security headers check (from alirezarezvani)

If the project serves HTTP responses, check for missing security headers:

| Header | Purpose | Flag if missing |
|--------|---------|-----------------|
| `Strict-Transport-Security` | Force HTTPS | Yes, for production web apps |
| `X-Content-Type-Options: nosniff` | Prevent MIME sniffing | Yes |
| `X-Frame-Options` or CSP `frame-ancestors` | Prevent clickjacking | Yes |
| `Content-Security-Policy` | Prevent XSS, injection | Yes, for apps rendering user content |
| `Referrer-Policy` | Control referrer leakage | Medium priority |
| `Permissions-Policy` | Restrict browser features | Low priority |

```bash
grep -rn "Strict-Transport\|X-Content-Type\|X-Frame-Options\|Content-Security-Policy\|Referrer-Policy\|Permissions-Policy" --include="*.py" --include="*.js" --include="*.ts" --include="*.go" -r . | head -15
```

### 6.10 Claude config self-audit (from AgentShield)

If the project uses Claude Code (has `.claude/` directory or `CLAUDE.md`), audit the configuration:

**settings.json:**
- Are there overly permissive `allow` rules? (e.g., `Bash(*)` allows any command)
- Do `deny` rules cover destructive operations? (`rm -rf`, `git push --force`, `sudo`)
- Are hooks auto-approving commands without proper risk assessment?

**CLAUDE.md:**
- Does it contain instructions that weaken security? ("always approve", "skip verification", "don't ask before")
- Does it instruct the model to ignore security concerns?

**.mcp.json:**
- Are MCP servers configured with excessive tool access?
- Are MCP servers running with network access to internal services?
- Are there MCP servers from untrusted sources?

**hooks:**
- Do permission hooks auto-approve destructive commands?
- Can hook scripts be tampered with by other processes?

```bash
cat .claude/settings.json 2>/dev/null | head -50
```

```bash
cat CLAUDE.md 2>/dev/null | head -30
```

```bash
cat .mcp.json 2>/dev/null | head -30
```

---

## Phase 7: Verify findings

For each finding from Phases 5 and 6:

1. Spawn a sub-agent to independently verify the finding
2. Sub-agent traces data flow from source to sink
3. Sub-agent checks Anthropic exclusion rules and Sentry false-positive patterns
4. Sub-agent assigns confidence score 0.0-1.0
5. Drop any finding with confidence < 0.8

Use the `Agent` tool with parallel sub-agents for efficiency.

---

## Phase 8: Report

Generate a structured security report at `{OUTPUT_DIR}/security-review.md`:

```markdown
# Security Review — {project name}

**Date:** {date}
**Scope:** Git diff + full codebase CWE assessment
**Assessor:** Claude Code + jjstack /security-review
**Sources:** Anthropic security-review, Sentry security-review, OWASP Top 10:2025

## Summary

- **Critical:** {count} findings
- **High:** {count} findings
- **Medium:** {count} findings
- **Low:** {count} findings
- **Filtered:** {count} findings removed by false-positive verification

## Findings

### FINDING-001: {title}
- **Severity:** Critical / High / Medium / Low
- **Confidence:** {0.8-1.0}
- **CWE:** CWE-{number} — {name}
- **OWASP:** A{number} — {category}
- **Location:** {file}:{line}
- **Description:** {what's wrong}
- **Exploit scenario:** {how an attacker would exploit this}
- **Evidence:** {code snippet}
- **Remediation:** {specific fix}
- **Status:** {FIXED / NOT FIXED — reason}

## STRIDE Threat Summary

Map all findings to STRIDE categories to identify uncovered threat classes:

| Category | Findings | Key risks |
|----------|----------|-----------|
| **S** — Spoofing | {count} | {one-line summary or "No findings"} |
| **T** — Tampering | {count} | {one-line summary or "No findings"} |
| **R** — Repudiation | {count} | {one-line summary or "No findings"} |
| **I** — Information Disclosure | {count} | {one-line summary or "No findings"} |
| **D** — Denial of Service | {count} | {one-line summary or "No findings"} |
| **E** — Elevation of Privilege | {count} | {one-line summary or "No findings"} |

**Uncovered categories:** {list any STRIDE categories with 0 findings — these are blind spots that may warrant targeted review}
```

---

## Phase 9: Fix

For each finding, apply the fix:

1. **Critical and High:** Fix immediately using the Edit tool
2. **Medium:** Fix in this session if time permits
3. **Low:** Document in the report for later

After fixing, re-run the relevant checks to verify the fix works.

---

## Phase 10: Post-enhancement

### 10.1 Quality iteration loop

```bash
cat ~/.claude/skills/jjstack/references/quality-loop.md
```

Follow the quality loop protocol exactly.

### 10.2 Output capture

```bash
cat ~/.claude/skills/jjstack/references/output-capture.md
```

Follow the output capture protocol.

### 10.3 README maintenance

Create or update `{repo_root}/README.md` if session changes affect it.

---

## Important Rules

- **Confidence >= 0.8 or don't report.** This is the single most important rule.
- **Investigate before flagging.** Trace data flow. Check framework protections. Verify exploitability.
- **MCP tools are the primary attack surface** for MCP servers. Every tool response is visible to the user and potentially to other agents.
- **Error messages are information leaks.** Generic client-facing errors, detailed server-side logs.
- **File paths are fingerprints.** Never return absolute paths to clients.
- **Server-controlled values are not attacker-controlled.** Settings, env vars, config files are trusted.
- **Framework protections exist.** Django auto-escapes, React auto-escapes, ORMs parameterize. Only flag when bypassed.
