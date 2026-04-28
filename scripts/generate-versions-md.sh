#!/bin/bash
#
# Generates a markdown file containing version and commit information 
# for the components used in the build.
#
# Usage:
#   ./generate-versions-md.sh <git-version> <rsync-src-dir> <git-sdk-dir> <output-file>

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <git-version> <rsync-src-dir> <git-sdk-dir> <output-file>" >&2
  exit 1
fi

GIT_VER="$1"
RSYNC_DIR="$2"
SDK_DIR="$3"
OUTPUT_FILE="$4"

echo "Generating versions markdown..."

# Get rsync version (e.g., v3.3.0) and commit hash
if [[ -d "${RSYNC_DIR}/.git" ]]; then
  RSYNC_VERSION=$(git -C "${RSYNC_DIR}" describe --tags --always 2>/dev/null || echo "Unknown")
  RSYNC_COMMIT=$(git -C "${RSYNC_DIR}" rev-parse HEAD 2>/dev/null || echo "Unknown")
else
  RSYNC_VERSION="Unknown (Not a git repo)"
  RSYNC_COMMIT="Unknown"
fi

# Get git-sdk-64 commit hash
if [[ -d "${SDK_DIR}/.git" ]]; then
  SDK_COMMIT=$(git -C "${SDK_DIR}" rev-parse HEAD 2>/dev/null || echo "Unknown")
else
  SDK_COMMIT="Unknown (Not a git repo)"
fi

# Attempt to fetch the Git commit hash using the GitHub API based on the tag
GIT_TAG="v${GIT_VER}"
# The API might return multiple results or a message if rate-limited, so we handle it carefully.
GIT_COMMIT=$(curl -s "https://api.github.com/repos/git-for-windows/git/git/refs/tags/${GIT_TAG}" | grep -E '"sha":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "")

if [[ -z "${GIT_COMMIT}" ]]; then
  GIT_COMMIT="-"
fi

cat <<EOF > "${OUTPUT_FILE}"
# Build Components & Versions

This package was built using the following components and exact commits to guarantee runtime compatibility with Git for Windows.

| Component | Version / Tag | Commit Hash |
| :--- | :--- | :--- |
| **Git for Windows** | \`${GIT_VER}\` | \`${GIT_COMMIT}\` |
| **git-sdk-64** | - | \`${SDK_COMMIT}\` |
| **rsync** | \`${RSYNC_VERSION}\` | \`${RSYNC_COMMIT}\` |
EOF

echo "Successfully wrote versions to ${OUTPUT_FILE}"
