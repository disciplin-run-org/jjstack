---
name: github-setup
description: >
  Automate GitHub repo initialization and configuration. Creates repos with correct
  settings (private default, MIT license for public), generates .gitignore and README,
  installs a semver auto-bump GitHub Action driven by conventional commits, and audits
  existing repos against conventions. Trigger on "set up GitHub", "create repo",
  "add version bumping", "audit repo settings", or when configuring a new project.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
  - Write
  - Edit
---

# GitHub Setup — Repo Initialization & Configuration

## Preamble

```bash
_UPD=$(~/.claude/skills/jjstack/bin/jjstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
```

If output contains `UPGRADE_AVAILABLE`: follow the upgrade flow from the plan-ceo-review skill.

---

## Phase 0: Detect Mode

Run these checks to determine which mode to operate in:

```bash
git rev-parse --show-toplevel 2>/dev/null || echo "NO_GIT_REPO"
```

```bash
gh repo view --json name,visibility,defaultBranchRef 2>/dev/null || echo "NO_GITHUB_REMOTE"
```

```bash
ls .github/workflows/version-bump.yml 2>/dev/null || echo "NO_VERSION_WORKFLOW"
```

Based on results:
- No git repo at all → **Mode A: New Repo Setup**
- Git repo but no GitHub remote → **Mode A** (will create the remote)
- GitHub remote but no version-bump workflow → **Mode B: Add Semver Workflow**
- Everything present → **Mode C: Audit**

If multiple modes could apply, ask the user via AskUserQuestion which they want.

---

## Mode A: New Repo Setup

### A.1 Gather information

Ask the user via AskUserQuestion:

1. **Repo name** — default: `basename` of current directory
2. **Visibility** — default: **private**. Options: private, public
3. **License** (only if public) — default: **MIT**. Options: MIT, Apache 2.0, None
4. **Project type** — auto-detect, confirm with user:
   - `pyproject.toml` or `*.py` present → Python
   - `package.json` present → Node.js
   - Otherwise → General

### A.2 Initialize local git repo (if needed)

```bash
git init
```

```bash
git checkout -b main
```

### A.3 Generate .gitignore

Select the appropriate template based on project type.

**Python .gitignore:**

```
__pycache__/
*.pyc
*.pyo
.venv/
venv/
dist/
*.egg-info/
.eggs/
.mypy_cache/
.pytest_cache/
.ruff_cache/
.env
.idea/
.vscode/
*.so
.install-manifest
```

**Node.js .gitignore:**

```
node_modules/
dist/
.env
.next/
.astro/
coverage/
*.tsbuildinfo
npm-debug.log*
.idea/
.vscode/
.DS_Store
.install-manifest
```

**General .gitignore:**

```
.env
.idea/
.vscode/
*.log
.DS_Store
Thumbs.db
.install-manifest
```

Write the selected template to `.gitignore`.

### A.4 Generate VERSION

```
0.1.0
```

Write to `VERSION`.

### A.5 Generate README.md

```markdown
# {repo-name}

> {one-line description — ask the user or use "TODO: Add description"}

## Setup

TODO

## License

{MIT if public, "Private" if private}
```

### A.6 Generate LICENSE (if public + MIT)

Write the standard MIT license text:

```
MIT License

Copyright (c) {current year} {user's GitHub username or name}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Get the current year:

```bash
date +%Y
```

Get the GitHub username:

```bash
gh api user --jq '.name // .login'
```

### A.7 Create GitHub repo

```bash
gh repo create {owner}/{name} --{visibility} --source=. --remote=origin --push
```

### A.8 Configure repo settings

```bash
gh repo edit --enable-issues --enable-wiki --enable-projects
```

```bash
gh repo edit --enable-merge-commit --enable-squash-merge --enable-rebase-merge
```

```bash
gh repo edit --delete-branch-on-merge
```

### A.9 Initial commit and push

Stage all generated files:

```bash
git add .gitignore README.md VERSION
```

Also add LICENSE if it was created.

```bash
git commit -m "chore: initial project setup"
```

```bash
git push -u origin main
```

### A.10 Proceed to Mode B

After the repo is created, install the semver workflow.

---

## Mode B: Semver Auto-Bump GitHub Action

Create `.github/workflows/version-bump.yml` with this exact content:

```yaml
name: Version Bump

on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  bump:
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Determine bump type from commits
        id: bump
        run: |
          LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
          if [ -z "$LAST_TAG" ]; then
            COMMITS=$(git log --format="%s" HEAD)
          else
            COMMITS=$(git log --format="%s" "$LAST_TAG"..HEAD)
          fi

          BUMP="none"

          if echo "$COMMITS" | grep -qiE '^[a-z]+(\(.+\))?!:|BREAKING CHANGE'; then
            BUMP="major"
          elif echo "$COMMITS" | grep -qE '^feat(\(.+\))?:'; then
            BUMP="minor"
          elif echo "$COMMITS" | grep -qE '^fix(\(.+\))?:'; then
            BUMP="patch"
          fi

          echo "bump=$BUMP" >> "$GITHUB_OUTPUT"

      - name: Bump version
        if: steps.bump.outputs.bump != 'none'
        run: |
          BUMP="${{ steps.bump.outputs.bump }}"
          CURRENT=$(cat VERSION 2>/dev/null || echo "0.0.0")
          IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

          case "$BUMP" in
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            patch) PATCH=$((PATCH + 1)) ;;
          esac

          NEW="$MAJOR.$MINOR.$PATCH"
          echo "$NEW" > VERSION

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add VERSION
          git commit -m "chore: bump version to $NEW [skip ci]"
          git tag "v$NEW"
          git push origin main --tags
```

**Key design decisions:**
- `[skip ci]` in the auto-commit prevents infinite workflow loops
- Scans ALL commits since last tag (handles squash merges and batched pushes)
- Priority: major > minor > patch (any breaking commit = major bump)
- Uses built-in `GITHUB_TOKEN` — no Personal Access Token needed
- `github-actions[bot]` as committer so auto-bumps are clearly automated
- VERSION file is the single source of truth (matches `jjstack-update-check` format)

After creating the workflow:

```bash
mkdir -p .github/workflows
```

Write the file, then:

```bash
git add .github/workflows/version-bump.yml
```

```bash
git commit -m "feat: add semver auto-bump GitHub Action"
```

```bash
git push
```

---

## Mode C: Audit Existing Repo

Run these checks and print a checklist:

### Checks

1. **Default branch is `main`:**
   ```bash
   gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
   ```

2. **Visibility:**
   ```bash
   gh repo view --json visibility --jq '.visibility'
   ```

3. **License (if public):**
   ```bash
   gh repo view --json licenseInfo --jq '.licenseInfo.spdxId'
   ```

4. **.gitignore exists:**
   ```bash
   test -f .gitignore && echo "EXISTS" || echo "MISSING"
   ```

5. **VERSION file exists:**
   ```bash
   test -f VERSION && echo "EXISTS" || echo "MISSING"
   ```

6. **version-bump workflow exists:**
   ```bash
   test -f .github/workflows/version-bump.yml && echo "EXISTS" || echo "MISSING"
   ```

7. **Repo features:**
   ```bash
   gh repo view --json hasIssuesEnabled,hasWikiEnabled,hasProjectsEnabled,mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed,deleteBranchOnMerge
   ```

### Output format

```
Repo audit: {owner}/{name}
  [pass] Default branch: main
  [pass] Visibility: private
  [skip] License check (private repo)
  [pass] .gitignore exists
  [FAIL] VERSION file missing
  [FAIL] version-bump workflow missing
  [pass] Issues enabled
  [pass] Wiki enabled
  [pass] Projects enabled
  [pass] Merge commit allowed
  [pass] Squash merge allowed
  [pass] Rebase merge allowed
  [pass] Delete branch on merge

2 issues found. Fix now?
```

If the user says yes, fix each failure:
- Missing VERSION → create with `0.1.0`
- Missing workflow → install via Mode B
- Missing .gitignore → generate via Mode A.3
- Wrong repo settings → fix via `gh repo edit`
- Missing license (public repo) → generate via Mode A.6

---

## Conventions Reference

These are the GitHub conventions this skill enforces:

| Setting | Convention |
|---------|-----------|
| Default branch | `main` |
| Visibility | Private by default |
| License (public) | MIT |
| Commit format | Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:` |
| Merge strategies | All three enabled (squash, rebase, merge commit) |
| Delete branch on merge | Yes |
| Issues | Enabled |
| Wiki | Enabled |
| Projects | Enabled |
| GPG signing | Not enforced |
| CODEOWNERS | Not used |
| Git protocol | HTTPS |
| Version tracking | `VERSION` file + semver auto-bump Action |
