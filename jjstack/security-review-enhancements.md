# Recommended Enhancements for jjstack /security-review

**Date:** 2026-03-30
**Based on:** Analysis of 24 community security skills for Claude Code
**Current skill:** `skills/security-review/SKILL.md` v0.1.0

---

## Priority 1: Critical gaps (our skill lacks these entirely)

### E-001: Confidence scoring and false-positive suppression
- **Source:** Anthropic official `/security-review` (4,100 stars), Sentry `security-review` (493 stars)
- **Gap:** Our skill has no mechanism to filter false positives. Every grep match gets reported.
- **What to add:**
  - Confidence score 0.0-1.0 on each finding; only report >= 0.8
  - Hard exclusion rules: don't flag DoS/rate-limiting, test files, log format strings, informational severity
  - Precedent rules: UUIDs are safe IDs, env vars read at startup are trusted, React auto-escapes JSX, ORM parameterizes queries, `crypto.randomBytes` is safe
  - Investigation-first methodology (Sentry): "Do NOT report issues based solely on pattern matching. Investigate first." — trace data flow from source to sink before reporting
- **Impact:** Dramatically reduces noise. Sentry's skill was rated the only one "worth installing" out of 5 tested, specifically because of low false positives.

### E-002: Secret detection patterns
- **Source:** CodyLunders hooks-library, afiqiqmal security-audit, wshobson `security-scan`
- **Gap:** Our skill only greps for generic keywords (`API_KEY`, `TOKEN`). No regex patterns for actual secret formats.
- **What to add:** 14+ regex patterns for real secrets:
  - `AKIA[0-9A-Z]{16}` — AWS access keys
  - `ghp_[a-zA-Z0-9]{36}` — GitHub personal access tokens
  - `sk-[a-zA-Z0-9]{48}` — OpenAI/Anthropic API keys
  - `-----BEGIN (RSA |EC )?PRIVATE KEY-----` — PEM private keys
  - `xoxb-[0-9]{10,13}-[a-zA-Z0-9-]{24}` — Slack bot tokens
  - Stripe, Twilio, SendGrid, database connection strings, JWT tokens
- **Impact:** Catches real leaked secrets instead of just variable names.

### E-003: Framework-aware analysis
- **Source:** Sentry (17 reference files), agamm OWASP (20 language guides)
- **Gap:** Our skill is Python-only. No awareness of framework-specific safe patterns.
- **What to add:**
  - Language detection at discovery phase (Python, JS/TS, Go, Rust, Java, Ruby, PHP, Shell)
  - Framework-specific safe patterns: Django ORM parameterizes, React auto-escapes JSX, Express `res.json()` is safe, Go `html/template` auto-escapes
  - Framework-specific danger patterns: Django `|safe` filter, React `dangerouslySetInnerHTML`, Express `res.send(userInput)`, Go `text/template` doesn't escape
  - Expand grep patterns beyond `--include="*.py"` to match detected languages
- **Impact:** Makes the skill useful for any project, not just Python.

### E-004: Dependency/supply chain scanning
- **Source:** Trail of Bits `supply-chain-risk-auditor`, afiqiqmal, Sentry `skill-scanner`
- **Gap:** Our skill checks code but ignores dependencies entirely.
- **What to add:**
  - Check `package.json`/`requirements.txt`/`go.mod`/`Cargo.toml` for known vulnerable packages
  - Run `npm audit` / `pip audit` / `cargo audit` if available
  - Flag pinned vs unpinned dependencies
  - Check for typosquatting patterns in package names
  - Check `package.json` for suspicious `preinstall`/`postinstall` lifecycle scripts
- **Impact:** Supply chain is a top attack vector. Dependencies are often the weakest link.

---

## Priority 2: High-value additions

### E-005: Hardcoded secret detection in git history
- **Source:** wshobson `security-scan`, harish-garg security-scanner
- **Gap:** We only scan current files, not git history.
- **What to add:**
  ```bash
  git log --all -p --diff-filter=D -- "*.env" "*.pem" "*.key" | head -100
  ```
  - Check if secrets were committed and then deleted (still in history)
  - Flag repos without `.gitignore` entries for `.env`, `*.pem`, `*.key`
- **Impact:** Secrets in git history are a common real-world breach vector.

### E-006: Modes of operation
- **Source:** afiqiqmal (`quick`, `full`, `diff`, `focus:auth`), Anthropic (diff-only)
- **Gap:** Our skill always runs the full assessment. No way to scope it.
- **What to add:**
  - `diff` mode — only review changed files (fast, for pre-commit/PR)
  - `full` mode — current behavior (deep CWE + diff)
  - `focus:auth` / `focus:injection` / `focus:secrets` — deep-dive into one category
  - Detect mode from user's invocation context (e.g., if called during PR flow, default to `diff`)
- **Impact:** Makes the skill practical for daily use, not just periodic audits.

### E-007: Agentic AI / MCP-specific security checks
- **Source:** agamm OWASP (ASI01-ASI10), affaan-m AgentShield, Sentry `skill-scanner`
- **Gap:** Our MCP checks are good but miss AI-specific attack vectors.
- **What to add:**
  - Prompt injection in MCP tool inputs (can a user craft input that changes agent behavior?)
  - Tool permission escalation (does a tool grant more access than its description implies?)
  - MCP tool chaining attacks (can tool A's output be used to exploit tool B?)
  - Agent memory poisoning (can tool responses inject instructions into conversation context?)
  - CLAUDE.md / settings.json audit (are hooks or skills configured insecurely?)
  - Check MCP server configs in `.mcp.json` for over-permissive tool access
- **Impact:** This is jjstack's home turf — MCP security. We should be the best at this.

### E-008: OWASP Top 10 (2025) structured coverage
- **Source:** agamm OWASP, afiqiqmal, claudedirectory
- **Gap:** Our CWE checks cover 6 CWEs but don't map to the OWASP Top 10 systematically.
- **What to add:** Explicit checks for each OWASP Top 10 category:
  - A01: Broken Access Control (IDOR, missing authorization on endpoints)
  - A02: Cryptographic Failures (weak algorithms, hardcoded keys, HTTP for sensitive data)
  - A03: Injection (SQL, OS command, LDAP, XPath — we have some, need completeness)
  - A04: Insecure Design (missing rate limiting, no account lockout)
  - A05: Security Misconfiguration (debug mode, default credentials, unnecessary features)
  - A06: Vulnerable Components (covered by E-004)
  - A07: Authentication Failures (weak password rules, missing MFA, session fixation)
  - A08: Data Integrity Failures (unsigned updates, insecure deserialization)
  - A09: Logging Failures (we have CWE-532, need completeness)
  - A10: SSRF (we have CWE-918, good)
- **Impact:** Industry-standard coverage. Makes the report credible for compliance.

### E-009: Confidence-based sub-task filtering
- **Source:** Anthropic official `/security-review`
- **Gap:** Our skill reports findings inline. No parallel verification step.
- **What to add:**
  - After initial scan, spawn a sub-agent per finding to verify it's real
  - Sub-agent traces data flow from source to sink
  - Sub-agent assigns confidence score
  - Only findings with confidence >= 0.8 make it into the report
  - Use `Agent` tool with `subagent_type=general-purpose` for parallel verification
- **Impact:** Higher-quality reports. Eliminates the "wall of false positives" problem.

---

## Priority 3: Nice-to-have enhancements

### E-010: Security headers check (for web apps)
- **Source:** alirezarezvani `senior-security`, wshobson `security-scan`
- **What to add:** Check for missing security headers in responses:
  - `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`
  - `Content-Security-Policy`, `Referrer-Policy`, `Permissions-Policy`
  - Can be checked in code (middleware/config) or via live endpoint if URL provided

### E-011: Compliance framework mapping
- **Source:** afiqiqmal (9 frameworks), pitimon (6 frameworks)
- **What to add:** Map findings to compliance frameworks:
  - OWASP Top 10 (2025), CWE, NIST CSF 2.0
  - Optional: PCI DSS 4.0, SOC 2, ISO 27001 (when relevant)
  - Add framework tags to each finding in the report

### E-012: STRIDE threat modeling
- **Source:** fr33d3m0n (1,900+ patterns), alirezarezvani
- **What to add:** After the scan, generate a lightweight STRIDE threat model:
  - Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege
  - Map findings to STRIDE categories
  - Identify un-covered threat categories

### E-013: GitHub Actions / CI/CD security
- **Source:** Sentry `gha-security-review` (only dedicated GHA security skill)
- **What to add:** If `.github/workflows/` exists:
  - Check for `${{ }}` expression injection in `run:` blocks
  - Check for `pull_request_target` with checkout of PR branch (pwn request)
  - Check for overly permissive `permissions:` (write-all)
  - Check for unpinned actions (`uses: actions/checkout@main` vs `@v4`)

### E-014: Docker/container security
- **Source:** Trail of Bits, pitimon, wshobson
- **What to add:** If `Dockerfile` exists:
  - Running as root? (`USER` directive missing)
  - Using `latest` tag? (unpinned base image)
  - Copying secrets into image? (`COPY .env`, `COPY *.key`)
  - Exposing unnecessary ports?
  - Multi-stage build to exclude build tools from production image?

### E-015: Live endpoint testing (optional, with permission)
- **Source:** afiqiqmal (gray-box testing), transilienceai
- **What to add:** If user provides a URL:
  - Check security headers on live responses
  - Test for CORS misconfiguration
  - Check for information disclosure in error responses (404, 500)
  - Test rate limiting on auth endpoints
  - Gate behind explicit user permission

---

## What NOT to add (and why)

| Considered | Rejected because |
|------------|-----------------|
| 753-skill mega-collections (mukul975) | Breadth without depth. Better to have 1 focused skill than 753 shallow ones. |
| Pentesting/offensive tools (transilienceai) | Out of scope. /security-review is defensive. /cso covers red-team. |
| SOAR integration (eth0izzle) | Vendor-specific (CrowdStrike). Not relevant for developer security review. |
| Bilingual support (pitimon) | English-only is fine for code review output. |
| SecLists integration (Eyadkelleh) | Payload lists are for active testing, not code review. |
| Full DREAD scoring (alirezarezvani) | Overkill for a code review. CVSS-like severity (C/H/M/L) is sufficient. |

---

## Recommended implementation order

1. **E-001** (false-positive suppression) + **E-009** (sub-task filtering) — biggest quality win
2. **E-002** (secret patterns) + **E-005** (git history) — highest real-world impact
3. **E-003** (framework-aware) — makes skill universally useful
4. **E-006** (modes) — makes skill practical for daily use
5. **E-007** (agentic AI) — our differentiator
6. **E-004** (dependency scanning) — low effort, high value
7. **E-008** (OWASP mapping) — completeness
8. **E-013** + **E-014** (CI/CD + Docker) — infrastructure coverage
9. **E-010** + **E-011** + **E-012** (headers, compliance, STRIDE) — polish

---

## Sources analyzed

| # | Source | Stars | Key takeaway |
|---|--------|-------|-------------|
| 1 | anthropics/claude-code-security-review | 4,100 | Confidence scoring + exclusion rules = low noise |
| 2 | getsentry/skills `security-review` | 493 | Investigation-first > pattern matching |
| 3 | getsentry/skills `gha-security-review` | 493 | GHA-specific exploit patterns |
| 4 | getsentry/skills `skill-scanner` | 493 | Scan skills before installing |
| 5 | getsentry/skills `django-access-review` | 493 | IDOR tracing methodology |
| 6 | agamm/claude-code-owasp | 56 | 20-language coverage + ASI01-10 |
| 7 | afiqiqmal/claude-security-audit | — | 9 compliance frameworks, modes |
| 8 | trailofbits/skills | — | 36 professional security plugins |
| 9 | transilienceai/communitytools | — | 100% CTF score, 23 skills |
| 10 | mukul975/Anthropic-Cybersecurity-Skills | 3,900 | 753 skills (breadth play) |
| 11 | Eyadkelleh/awesome-claude-skills-security | — | SecLists integration |
| 12 | pitimon/claude-cybersecurity-skill | — | 22 domains, compliance mapping |
| 13 | fr33d3m0n/threat-modeling | — | STRIDE + 1,900 threat patterns |
| 14 | eth0izzle/security-skills | 34 | CrowdStrike SOAR |
| 15 | alirezarezvani/claude-skills | — | STRIDE+DREAD, auth matrix |
| 16 | wshobson/commands | — | 57 commands, security-scan |
| 17 | harish-garg/security-scanner-plugin | — | GitHub Dependabot integration |
| 18 | MaTriXy/github-review-skill | — | GitHub security alerts |
| 19 | CodyLunders/claude-code-hooks-library | — | 12 security hooks, secret regex |
| 20 | Pixelmojo hooks article | — | Critical file protection patterns |
| 21 | jeffallan.github.io | — | SAST tool integration |
| 22 | claudedirectory.org | — | OWASP scan template |
| 23 | VoltAgent subagents | — | Opus pentest subagent |
| 24 | affaan-m AgentShield | — | Claude config self-audit |
