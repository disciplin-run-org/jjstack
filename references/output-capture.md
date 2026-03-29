# Output Capture Protocol

gstack skills write output to `~/.gstack/projects/$SLUG/` via hardcoded bash commands
that bypass jjstack's natural language path override. This protocol runs after every
gstack delegation to copy any files that landed in the gstack directory to the
jjstack output directory.

## Step 1: Detect the gstack slug

```bash
~/.claude/skills/gstack/bin/gstack-slug > /tmp/gstack-slug.sh 2>/dev/null
source /tmp/gstack-slug.sh
echo "$SLUG"
```

If `$SLUG` is empty, try deriving it from the repo:

```bash
basename "$(git remote get-url origin 2>/dev/null)" .git 2>/dev/null
```

## Step 2: Copy files from gstack to jjstack output

```bash
rsync -a --ignore-existing ~/.gstack/projects/$SLUG/ {OUTPUT_DIR}/ 2>/dev/null
```

This copies any files that gstack wrote to its default location into the jjstack
output directory. `--ignore-existing` preserves files already in `{OUTPUT_DIR}`
(e.g., from a previous run or manual placement). If `rsync` is not available:

```bash
cp -rn ~/.gstack/projects/$SLUG/* {OUTPUT_DIR}/ 2>/dev/null
```

## Step 3: Also capture QA reports (if applicable)

If the skill is a QA skill (`/qa`, `/qa-only`), also capture from the in-repo
`.gstack/` directory:

```bash
rsync -a --ignore-existing .gstack/qa-reports/ {OUTPUT_DIR}/qa-reports/ 2>/dev/null
```

## Step 4: Report what was captured

```bash
ls {OUTPUT_DIR}/ 2>/dev/null
```

If new files appeared that weren't there before the gstack delegation, inform the
user: "Captured gstack output to `{OUTPUT_DIR}/`."

If `{OUTPUT_DIR}` is empty and `~/.gstack/projects/$SLUG/` is also empty, there
was no output to capture — this is normal for some skills.
