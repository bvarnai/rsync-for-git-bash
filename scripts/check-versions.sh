#!/bin/bash
#
# Check for latest rsync and Git for Windows versions and determine if a new release is needed.
#
# Usage:
#   ./check-versions.sh

set -euo pipefail

# Helper to fetch latest tag from a GitHub repo
get_latest_tag() {
    local repo=$1
    curl -s "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

RSYNC_TAG=$(get_latest_tag "RsyncProject/rsync")
GIT_TAG=$(get_latest_tag "git-for-windows/git")

if [[ -z "$RSYNC_TAG" || -z "$GIT_TAG" ]]; then
    # Fallback to tags if releases are not used consistently
    RSYNC_TAG=$(curl -s "https://api.github.com/repos/RsyncProject/rsync/tags" | grep '"name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
    GIT_TAG=$(curl -s "https://api.github.com/repos/git-for-windows/git/tags" | grep '"name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
fi

# Strip 'v' prefix
RSYNC_VER=${RSYNC_TAG#v}
GIT_VER=${GIT_TAG#v}

EXPECTED_TAG="rsync-${RSYNC_VER}-for-git-${GIT_VER}"

echo "Latest Rsync: $RSYNC_VER"
echo "Latest Git:   $GIT_VER"
echo "Expected Tag: $EXPECTED_TAG"

if git rev-parse "$EXPECTED_TAG" >/dev/null 2>&1; then
    echo "Release already exists for $EXPECTED_TAG."
    echo "needs_build=false" >> $GITHUB_OUTPUT
else
    echo "New release needed for $EXPECTED_TAG."
    echo "needs_build=true" >> $GITHUB_OUTPUT
    echo "rsync_ver=$RSYNC_VER" >> $GITHUB_OUTPUT
    echo "git_ver=$GIT_VER" >> $GITHUB_OUTPUT
    echo "tag_name=$EXPECTED_TAG" >> $GITHUB_OUTPUT
fi
