# The "Bump version" step of .github/workflows/version-bump.yml as shipped at
# af74fb1, the last version before releases became tags.
#
# It commits VERSION as a bot and runs `git push origin main --tags`. Under
# branch protection GitHub refuses main per ref and accepts the tag, so the
# first run orphans a tag and every run after it dies at `git tag` because
# the tag it computes already exists. This step IS the failure; it is not a
# script written to be wrong. The one GitHub expression in it,
# ${{ steps.bump.outputs.bump }}, is filled in by the test.
#
# Re-derive:  git show af74fb1:.github/workflows/version-bump.yml, step 'Bump version', run block
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
