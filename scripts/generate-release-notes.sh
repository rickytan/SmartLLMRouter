#!/usr/bin/env bash
# generate-release-notes.sh
# Generates release notes from git log, excluding docs/CI-only commits.
# Usage: bash scripts/generate-release-notes.sh [prev_tag] [current_sha]

set -euo pipefail

PREV_TAG="${1:-}"
CURRENT_SHA="${2:-$GITHUB_SHA}"

if [ -z "$PREV_TAG" ]; then
  # Try to find previous tag
  PREV_TAG=$(git tag --sort=-creatordate | grep -A1 "${GITHUB_REF#refs/tags/}" | tail -1)
fi

if [ -z "$PREV_TAG" ]; then
  RANGE="$CURRENT_SHA"
else
  RANGE="${PREV_TAG}..${CURRENT_SHA}"
fi

NOTES=""
for hash in $(git log "$RANGE" --no-merges --pretty=format:"%H"); do
  MSG=$(git log -1 --pretty=format:"%s (%an)" "$hash")
  FILES=$(git diff-tree --no-commit-id --name-only -r "$hash")

  ALL_EXCLUDED=true
  while IFS= read -r file; do
    case "$file" in
      *.md|docs/*|.github/*|fastlane/*|scripts/*|LICENSE|.gitignore) ;;
      *) ALL_EXCLUDED=false; break ;;
    esac
  done <<< "$FILES"

  if [ "$ALL_EXCLUDED" = "false" ]; then
    NOTES="$NOTES
- $MSG"
  fi
done

# Trim leading newlines
NOTES="${NOTES#"${NOTES%%[!$'\n']*}"}"

if [ -z "$NOTES" ]; then
  NOTES="No user-facing changes in this release."
fi

# Escape for GitHub Actions multiline output
NOTES="${NOTES//'%'/'%25'}"
NOTES="${NOTES//$'\n'/'%0A'}"
NOTES="${NOTES//$'\r'/'%0D'}"

echo "body<<EOF"
echo "$NOTES"
echo "EOF"
