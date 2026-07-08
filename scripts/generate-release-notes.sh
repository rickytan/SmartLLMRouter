#!/usr/bin/env bash
# generate-release-notes.sh
# Generates release notes from git log, excluding docs/CI-only commits.
# Usage: bash scripts/generate-release-notes.sh [prev_tag] [current_sha]

set -euo pipefail

PREV_TAG="${1:-}"
CURRENT_SHA="${2:-${GITHUB_SHA:-HEAD}}"
CURRENT_TAG=""

if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
  CURRENT_TAG="${GITHUB_REF#refs/tags/}"
else
  CURRENT_TAG=$(git describe --tags --exact-match "$CURRENT_SHA" 2>/dev/null || true)
fi

if [ -z "$PREV_TAG" ]; then
  if [ -n "$CURRENT_TAG" ] && git rev-parse -q --verify "$CURRENT_TAG^" >/dev/null; then
    PREV_TAG=$(git describe --tags --abbrev=0 "$CURRENT_TAG^" 2>/dev/null || true)
  else
    PREV_TAG=$(git describe --tags --abbrev=0 "$CURRENT_SHA^" 2>/dev/null || true)
  fi
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

DELIMITER="RELEASE_NOTES_$(date +%s)"
echo "body<<$DELIMITER"
echo "$NOTES"
echo "$DELIMITER"
