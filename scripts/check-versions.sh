#!/bin/bash
#
# Check for latest rsync and Git for Windows versions and determine if a new release is needed.
#
# Usage:
#   ./check-versions.sh

set -euo pipefail

# Perform a GitHub API GET request, authenticating when GITHUB_TOKEN or GH_TOKEN is set.
gh_api_get() {
  local url="$1"
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [[ -n "${token}" ]]; then
    curl -sS -H "Authorization: Bearer ${token}" "${url}" || true
  else
    curl -sS "${url}" || true
  fi
}

# Helper to fetch latest release tag from a GitHub repo, falling back to /tags.
get_latest_tag() {
  local repo="$1"
  local tag=""
  tag=$(gh_api_get "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -z "${tag}" ]]; then
    tag=$(gh_api_get "https://api.github.com/repos/${repo}/tags" | grep '"name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  fi
  echo "${tag}"
}

# Check whether a Git tag or GitHub release (including drafts) already exists for the expected tag.
release_exists() {
  local expected_tag="$1"
  if git rev-parse "${expected_tag}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v gh >/dev/null 2>&1 && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    local -a gh_args=(release list --limit 100 --json tagName --jq '.[].tagName')
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
      gh_args+=(--repo "${GITHUB_REPOSITORY}")
    fi
    if gh "${gh_args[@]}" 2>/dev/null | grep -Fxq "${expected_tag}"; then
      return 0
    fi
  fi

  return 1
}

RSYNC_TAG=$(get_latest_tag "RsyncProject/rsync")
GIT_TAG=$(get_latest_tag "git-for-windows/git")

# Strip 'v' prefix
RSYNC_VER="${RSYNC_TAG#v}"
GIT_VER="${GIT_TAG#v}"

if [[ -z "${RSYNC_VER}" || -z "${GIT_VER}" ]]; then
  echo "Error: Could not determine latest rsync ('${RSYNC_VER}') or Git for Windows ('${GIT_VER}') version." >&2
  exit 1
fi

EXPECTED_TAG="rsync-${RSYNC_VER}-for-git-${GIT_VER}"

echo "Latest Rsync: ${RSYNC_VER}"
echo "Latest Git:   ${GIT_VER}"
echo "Expected Tag: ${EXPECTED_TAG}"

if release_exists "${EXPECTED_TAG}"; then
  echo "Release or draft already exists for ${EXPECTED_TAG}."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "needs_build=false" >> "${GITHUB_OUTPUT}"
  fi
else
  echo "New release needed for ${EXPECTED_TAG}."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "needs_build=true"
      echo "rsync_ver=${RSYNC_VER}"
      echo "git_ver=${GIT_VER}"
      echo "tag_name=${EXPECTED_TAG}"
    } >> "${GITHUB_OUTPUT}"
  fi
fi
