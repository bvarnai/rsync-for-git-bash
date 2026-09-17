#!/bin/bash
#
# Setup dependencies for rsync-for-git-bash (git-sdk-64 and rsync).
#
# Usage:
#   ./setup-deps.sh <rsync-version> <sdk-commit> [deps-dir]
#
# Examples:
#   ./setup-deps.sh 3.5.0 0fb599c0f49fb69f8bd08260ac3c366cff1d7157
#   ./setup-deps.sh 3.5.0 0fb599c0f49fb69f8bd08260ac3c366cff1d7157 ./deps

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR: $*" >&2
  exit 1
}

if [[ $# -lt 2 ]]; then
  err "Usage: $0 <rsync-version> <sdk-commit> [deps-dir]"
fi

readonly RSYNC_VER="${1#v}"
readonly SDK_COMMIT="$2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)"

if [[ $# -ge 3 && -n "$3" ]]; then
  readonly DEPS_DIR="$(realpath "$3")"
else
  readonly DEPS_DIR="${REPO_ROOT}/deps"
fi

mkdir -p "${DEPS_DIR}"

readonly GIT_SDK_64="${DEPS_DIR}/git-sdk-64"
readonly RSYNC_SRC="${DEPS_DIR}/rsync"

# 1. Setup git-sdk-64
log "Setting up git-sdk-64 at commit ${SDK_COMMIT}..."
if [[ ! -d "${GIT_SDK_64}/.git" ]]; then
  log "Initializing git-sdk-64 (shallow fetch of target commit)..."
  mkdir -p "${GIT_SDK_64}"
  (
    cd "${GIT_SDK_64}"
    git init
    git remote add origin https://github.com/git-for-windows/git-sdk-64.git
    git fetch origin "${SDK_COMMIT}" --depth 1
    git checkout FETCH_HEAD
  )
else
  log "Checking local git-sdk-64 for commit ${SDK_COMMIT}..."
  if ! git -C "${GIT_SDK_64}" cat-file -e "${SDK_COMMIT}^{commit}" 2>/dev/null; then
    log "Fetching commit ${SDK_COMMIT}..."
    git -C "${GIT_SDK_64}" fetch origin "${SDK_COMMIT}" --depth 1 || git -C "${GIT_SDK_64}" fetch --depth 500 origin main
  fi
  git -C "${GIT_SDK_64}" checkout "${SDK_COMMIT}"
fi

# 2. Setup rsync source
log "Setting up rsync source v${RSYNC_VER}..."
if [[ ! -d "${RSYNC_SRC}/.git" ]]; then
  log "Cloning rsync v${RSYNC_VER}..."
  git clone --depth 1 --branch "v${RSYNC_VER}" https://github.com/RsyncProject/rsync.git "${RSYNC_SRC}"
else
  log "Fetching rsync tag v${RSYNC_VER}..."
  git -C "${RSYNC_SRC}" fetch --depth 1 origin "tags/v${RSYNC_VER}" 2>/dev/null || true
  git -C "${RSYNC_SRC}" checkout "v${RSYNC_VER}"
fi

log "Dependencies setup complete in ${DEPS_DIR}"
