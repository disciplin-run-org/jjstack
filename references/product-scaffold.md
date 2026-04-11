# Product Scaffold — Standard Capability Structure

Every product in the ecosystem follows this capability structure. When
`product_init` scaffolds a new product, it creates these capabilities with
placeholder features and draft behaviors.

---

## Standard Capabilities

| Cap | Name | Kano Range | What belongs here |
|-----|------|-----------|-------------------|
| 1 | **MCP Core** | 1-2 | The tools without which the product is broken. CRUD, data model, the primary API contract. |
| 2 | **MCP Auxiliary** | 3 | Supporting tools you survive a day without. Validation, reordering, batch ops, product-specific GitHub integration (save/load/sync). |
| 3 | **MCP Extended** | 4-5 | Nice-to-have tools. Scoring, coverage, AI suggestions, import/export. |
| 4 | **Foundation** | — | Imported from Architrix shared library. GitHub auth, repo selection, settings, health endpoint, AI model config. Not re-specified per product. |
| 5 | **CLI Interface** | 7 | Claude Code as the thin CLI wrapper. How the CLI calls MCP tools. |
| 6 | **Web UI** | 5-8 | Browser experience. Pages, navigation, editor, dashboards. All calling MCP tools. |
| 10 | **Technical Specs** | — | ADRs for architecture, runtime, and infrastructure decisions. |
| 11 | **Design System** | — | Typography, colors, layout, component patterns. |

Caps 7-9 are reserved for product-specific needs that don't fit the standard
structure.

---

## Principles

### MCP is the product (Layer 8: API First)

Every user action maps to an MCP tool call. The CLI is a wrapper. The Web UI
calls the same tools. There is no behavior that exists only in the UI — if the
UI can do it, there's an MCP tool behind it.

### Kano level is per-behavior, not per-capability

A capability groups related tools. The Kano level on each behavior determines
QA depth and quality tolerance. A security behavior (Kano 1) can live inside
any capability.

### No duplication across capabilities

Each MCP tool appears in exactly one capability. If a tool could belong to
multiple capabilities, it goes in the one closest to its primary purpose.

### Foundation is imported, not specified

Cap 4 Foundation behaviors are defined once in the Architrix shared library
specs. Product specs reference them but don't re-specify how GitHub auth or
settings work. Only product-specific GitHub integration (what this product
DOES with the repo) goes in Cap 2 Auxiliary.

---

## Technical Specs Reserved Features

| Feature | Decisions |
|---------|-----------|
| 10.1 Security | Encryption at rest, auth factors, PII classification, access control model |
| 10.2 Runtime & Stack | Language, framework, version, containerization |
| 10.3 Data Storage | Flat file vs SQLite vs PostgreSQL, backup, migrations |

Additional 10.x features grow organically per product (10.4 AI Models,
10.5 Infrastructure, etc.).

---

## How tools use this scaffold

### product_init (LeanSpecs 1.1.1 / 7.4.1)

When creating a new product spec:
1. Accepts product_name, description, github_repo
2. Scaffolds product.json with Caps 1-6, 10, 11 as empty capabilities
3. Pre-creates 10.1 Security, 10.2 Runtime, 10.3 Data Storage as draft features
4. Pushes as a PR branch to GitHub
5. Returns the PR URL

### litmus (test fixture)

The litmus repo (JesperJurcenoks/litmus) contains a reference implementation
of this scaffold using a fictional product (Litmus Books). Used to verify
that LeanSpecs, iris-qa, and future tools handle the standard structure correctly.

---

## Example: LeanSpecs mapped to this scaffold

| Cap | Name | Tools |
|-----|------|-------|
| 1 | MCP Core | spec_create, spec_read, spec_update, spec_soft_delete, spec_hard_delete, spec_list, spec_restore |
| 2 | MCP Auxiliary | spec_validate, spec_reorder, spec_renumber, spec_move, spec_merge, bulk_update, product_init, github_save, github_reload |
| 3 | MCP Extended | scorecard, coverage_check, cleanliness_score, cleanliness_review, spelling_check, gherkin_generate, ai_suggest, docs_import |
| 4 | Foundation | settings_read, settings_update, github_status, github_repos, github_branches, ai_models, ai_test, switch_repo, health |
| 5 | CLI Interface | Claude Code calling MCP tools |
| 6 | Web UI | Hierarchy browser, behavior editor, coverage dashboard, settings page, AI actions panel |
| 10 | Technical Specs | Security ADRs, runtime decisions, data storage choices |
| 11 | Design System | Nordic Minimalism, 5 colors max, 2 primary fonts |
