#!/bin/bash
#
# Find the matching git-sdk-64 commit for a specific Git for Windows release.
#
# This script identifies the SDK commit corresponding to a Git for Windows release
# using GitHub APIs (instant, zero cloning) with local repository fallback.
#
# Usage:
#   ./find-sdk-commit.sh <git-version> [deps-path]
#
# Examples:
#   ./find-sdk-commit.sh 2.55.0.windows.5
#   ./find-sdk-commit.sh 2.55.0.windows.5 deps

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <git-version> [deps-path]" >&2
  echo "Example: $0 2.55.0.windows.5" >&2
  exit 1
fi

readonly GIT_VERSION="${1#v}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)"

# Target directory for dependencies (optional, defaults to deps/)
if [[ $# -ge 2 && -n "$2" ]]; then
  readonly DEPS_DIR="$(realpath "$2")"
else
  readonly DEPS_DIR="${REPO_ROOT}/deps"
fi

readonly BUILD_EXTRA="${DEPS_DIR}/build-extra"
readonly GIT_SDK_64="${DEPS_DIR}/git-sdk-64"

# Step 1: Normalize version string.
readonly BASE_VERSION=$(echo "$GIT_VERSION" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
readonly BUILD_NUM=$(echo "$GIT_VERSION" | sed -nE 's/^[0-9]+\.[0-9]+\.[0-9]+\.windows\.([0-9]+).*/\1/p')
echo "Step 1: Extracted base version: $BASE_VERSION (build: ${BUILD_NUM:-1})"

# Step 2: Identify the Release Date.
ISO_DATE=""

# Check local ReleaseNotes.md if available
if [[ -f "$BUILD_EXTRA/ReleaseNotes.md" ]]; then
  raw_date_line=""
  if [[ -n "$BUILD_NUM" ]]; then
    raw_date_line=$(grep -A 1 -E "# Git for Windows v${BASE_VERSION}\(${BUILD_NUM}\) Release Notes" "$BUILD_EXTRA/ReleaseNotes.md" | tail -n 1 || true)
  fi
  if [[ -z "$raw_date_line" || ! "$raw_date_line" =~ "Latest update" ]]; then
    raw_date_line=$(grep -A 1 -E "# Git for Windows v${BASE_VERSION}(\([0-9]+\))? Release Notes" "$BUILD_EXTRA/ReleaseNotes.md" | tail -n 1 || true)
  fi

  if [[ -n "$raw_date_line" && "$raw_date_line" =~ "Latest update" ]]; then
    clean_date=$(echo "$raw_date_line" | sed -e 's/Latest update: //' -e 's/\([0-9]\+\)\(st\|nd\|rd\|th\)/\1/')
    ISO_DATE=$(date -d "$clean_date" +%Y-%m-%d 2>/dev/null || true)
  fi
fi

# Fallback: Query GitHub API for the release date
if [[ -z "$ISO_DATE" ]]; then
  api_date=$(curl -s "https://api.github.com/repos/git-for-windows/git/releases/tags/v${GIT_VERSION}" | grep '"published_at":' | head -n 1 | sed -E 's/.*"([0-9]{4}-[0-9]{2}-[0-9]{2})T.*/\1/' || true)
  if [[ -z "$api_date" ]]; then
    api_date=$(curl -s "https://api.github.com/repos/git-for-windows/git/releases/tags/${GIT_VERSION}" | grep '"published_at":' | head -n 1 | sed -E 's/.*"([0-9]{4}-[0-9]{2}-[0-9]{2})T.*/\1/' || true)
  fi
  ISO_DATE="$api_date"
fi

if [[ -z "$ISO_DATE" ]]; then
  echo "Error: Could not determine release date for Git for Windows v$GIT_VERSION" >&2
  exit 1
fi
echo "Step 2: Identified release date: $ISO_DATE"

# Step 3: Determine MSYS2 Runtime Package Version if local build-extra exists
runtime_pkg="unknown"
if [[ -d "$BUILD_EXTRA/versions" ]]; then
  PKG_VER_FILE=""
  if [[ -n "$BUILD_NUM" && -f "$BUILD_EXTRA/versions/package-versions-${BASE_VERSION}.${BUILD_NUM}.txt" ]]; then
    PKG_VER_FILE="$BUILD_EXTRA/versions/package-versions-${BASE_VERSION}.${BUILD_NUM}.txt"
  elif [[ -f "$BUILD_EXTRA/versions/package-versions-$BASE_VERSION.txt" ]]; then
    PKG_VER_FILE="$BUILD_EXTRA/versions/package-versions-$BASE_VERSION.txt"
  else
    PKG_VER_FILE=$(find "$BUILD_EXTRA/versions" -name "package-versions-${BASE_VERSION}*.txt" ! -name "*MinGit*" 2>/dev/null | head -n 1 || true)
  fi

  if [[ -n "$PKG_VER_FILE" && -f "$PKG_VER_FILE" ]]; then
    runtime_pkg=$(grep "^msys2-runtime " "$PKG_VER_FILE" | cut -d' ' -f2 || echo "unknown")
    echo "Step 3: MSYS2 runtime package version: $runtime_pkg (from $(basename "$PKG_VER_FILE"))"
  fi
fi

# Step 4: Search the SDK History for matching commit
echo "Step 4: Resolving SDK commit for date ${ISO_DATE}..."
sdk_commit=""

# 4a: Check local git-sdk-64 repository if present
if [[ -d "$GIT_SDK_64/.git" ]]; then
  sdk_commit=$(git -C "$GIT_SDK_64" log --until="$ISO_DATE 23:59:59" -n 1 --format=%H 2>/dev/null || true)
  if [[ -z "$sdk_commit" && -f "$GIT_SDK_64/.git/shallow" ]]; then
    echo "Deepening local git-sdk-64 history..."
    git -C "$GIT_SDK_64" fetch --depth 500 origin main 2>/dev/null || true
    sdk_commit=$(git -C "$GIT_SDK_64" log --until="$ISO_DATE 23:59:59" -n 1 --format=%H 2>/dev/null || true)
  fi
fi

# 4b: Fast resolution via GitHub API (no local git-sdk-64 required)
if [[ -z "$sdk_commit" ]]; then
  echo "Querying GitHub API for git-sdk-64 commit..."
  sdk_commit=$(curl -s "https://api.github.com/repos/git-for-windows/git-sdk-64/commits?until=${ISO_DATE}T23:59:59Z&per_page=1" | grep -m 1 '"sha":' | sed -E 's/.*"([0-9a-f]{40})".*/\1/' || true)
fi

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

# Optional verification check of DLL blob hash if local git repo is present
if [[ -d "$GIT_SDK_64/.git" ]]; then
  if git -C "$GIT_SDK_64" cat-file -e "$sdk_commit^{commit}" 2>/dev/null; then
    echo "Blob ID for msys-2.0.dll in local commit:"
    git -C "$GIT_SDK_64" rev-parse "$sdk_commit:usr/bin/msys-2.0.dll" 2>/dev/null || true
  fi
fi
