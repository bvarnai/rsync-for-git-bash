#!/bin/bash
#
# Find the matching git-sdk-64 commit for a specific Git for Windows release.
#
# This script automates the manual steps of cross-referencing release notes,
# package versions, and repository history to find the SDK state used for a build.
#
# Usage:
#   ./find-sdk-commit.sh <git-version> <workspace-path>
#
# Example:
#   ./find-sdk-commit.sh 2.54.0.windows.1 .

set -euo pipefail

# Error out if incorrect number of arguments provided.
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <git-version> <workspace-path>" >&2
  echo "Example: $0 2.54.0.windows.1 /c/work/ext" >&2
  exit 1
fi

readonly GIT_VERSION="$1"
readonly WORKSPACE="$(realpath "$2")"

readonly BUILD_EXTRA="$WORKSPACE/build-extra"
readonly GIT_SDK_64="$WORKSPACE/git-sdk-64"

# Validate workspace repositories.
for repo in "$BUILD_EXTRA" "$GIT_SDK_64"; do
  if [[ ! -d "$repo/.git" ]]; then
    echo "Error: $repo is not a Git repository or does not exist." >&2
    exit 1
  fi
done

# Step 1: Normalize version string.
# Extracts the base version (e.g., 2.54.0) for file lookup.
readonly BASE_VERSION=$(echo "$GIT_VERSION" | sed -E 's/^v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
echo "Step 1: Extracted base version: $BASE_VERSION"

# Step 2: Identify the Release Date from ReleaseNotes.md.
# Looks for the header and grabs the "Latest update" line.
raw_date_line=$(grep -A 1 "# Git for Windows v$BASE_VERSION Release Notes" "$BUILD_EXTRA/ReleaseNotes.md" | tail -n 1)
if [[ -z "$raw_date_line" ]]; then
  echo "Error: Could not find release notes for v$BASE_VERSION in $BUILD_EXTRA/ReleaseNotes.md" >&2
  exit 1
fi

# Clean date string (remove "Latest update: " and ordinal suffixes like "20th").
clean_date=$(echo "$raw_date_line" | sed -e 's/Latest update: //' -e 's/\([0-9]\+\)\(st\|nd\|rd\|th\)/\1/')
# Convert to ISO format (YYYY-MM-DD) for Git filters.
readonly ISO_DATE=$(date -d "$clean_date" +%Y-%m-%d)
echo "Step 2: Identified release date: $ISO_DATE"

# Step 3: Determine MSYS2 Runtime Package Version.
readonly PKG_VER_FILE="$BUILD_EXTRA/versions/package-versions-$BASE_VERSION.txt"
if [[ ! -f "$PKG_VER_FILE" ]]; then
  echo "Error: Package version file not found: $PKG_VER_FILE" >&2
  exit 1
fi

runtime_pkg=$(grep "^msys2-runtime " "$PKG_VER_FILE" | cut -d' ' -f2)
echo "Step 3: MSYS2 runtime package version: $runtime_pkg"

# Step 4: Get current runtime fingerprint for verification.
# Only valid if running under the target Git version.
echo "Step 4: Current environment fingerprint (for verification):"
uname -a || echo "Warning: uname -a failed. Ensure you are in an MSYS2/Git Bash environment."

# Step 5: Search the SDK History for the matching commit.
echo "Step 5: Searching git-sdk-64 history..."
# Find the last commit on the release day.
sdk_commit=$(git -C "$GIT_SDK_64" log --until="$ISO_DATE 23:59:59" -n 1 --format=%H)

if [[ -z "$sdk_commit" ]]; then
  echo "Error: Could not find any commits in git-sdk-64 on or before $ISO_DATE." >&2
  exit 1
fi

echo "--------------------------------------------------------"
echo "MATCH FOUND"
echo "--------------------------------------------------------"
echo "Git Version:    $GIT_VERSION"
echo "Release Date:   $ISO_DATE"
echo "SDK Commit:     $sdk_commit"
echo "Runtime Pkg:    $runtime_pkg"
echo "--------------------------------------------------------"

# Final verification check of the DLL blob hash.
echo "Blob ID for msys-2.0.dll in this commit:"
git -C "$GIT_SDK_64" rev-parse "$sdk_commit:usr/bin/msys-2.0.dll"
