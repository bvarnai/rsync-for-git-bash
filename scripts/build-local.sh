#!/bin/bash
#
# Helper script to run the rsync-for-git-bash build pipeline locally on Windows.
#
# This script orchestrates:
#   1. Version detection (auto-detected latest or provided via arguments)
#   2. SDK snapshot resolution (find-sdk-commit.sh)
#   3. Fetching dependencies (setup-deps.sh)
#   4. Compiling rsync inside the git-sdk-64 MSYS2 environment (run-in-sdk.sh -> build-rsync.sh)
#   5. Generating build metadata (generate-versions-md.sh)
#   6. Packaging rsync with required runtime MSYS DLLs (run-in-sdk.sh -> package-rsync.sh)
#   7. Verifying generated binary and dist artifacts
#
# Usage:
#   ./scripts/build-local.sh [rsync-version] [git-version]
#
# Examples:
#   ./scripts/build-local.sh
#   ./scripts/build-local.sh 3.5.0 2.55.0.windows.5

set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR: $*" >&2
  exit 1
}

# Ensure script is executed from repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)"
cd "${REPO_ROOT}"

# Helper to fetch latest tag from a GitHub repo
get_latest_tag() {
  local repo="$1"
  local tag
  tag=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -z "$tag" ]]; then
    tag=$(curl -s "https://api.github.com/repos/${repo}/tags" | grep '"name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  fi
  echo "$tag"
}

# 1. Determine versions
if [[ $# -ge 1 && -n "${1}" ]]; then
  RSYNC_VER="${1#v}"
else
  log "Fetching latest Rsync version from GitHub..."
  RSYNC_TAG=$(get_latest_tag "RsyncProject/rsync")
  RSYNC_VER="${RSYNC_TAG#v}"
fi

if [[ $# -ge 2 && -n "${2}" ]]; then
  GIT_VER="${2#v}"
else
  log "Fetching latest Git for Windows version from GitHub..."
  GIT_TAG=$(get_latest_tag "git-for-windows/git")
  GIT_VER="${GIT_TAG#v}"
fi

if [[ -z "${RSYNC_VER}" || -z "${GIT_VER}" ]]; then
  err "Could not determine Rsync or Git for Windows version. Please provide them manually: $0 <rsync-version> <git-version>"
fi

log "=== Build Parameters ==="
log "Rsync Version:       ${RSYNC_VER}"
log "Git for Windows:     ${GIT_VER}"
log "Repository Root:     ${REPO_ROOT}"

DEPS_DIR="${REPO_ROOT}/deps"
BUILD_PREFIX="${REPO_ROOT}/build/rsync"
DIST_DIR="${REPO_ROOT}/dist"
mkdir -p "${DEPS_DIR}" "${BUILD_PREFIX}" "${DIST_DIR}"

# 2. Resolve matching SDK commit
log "Step 2: Resolving SDK commit for Git for Windows ${GIT_VER}..."
SDK_OUTPUT=$(bash "${SCRIPT_DIR}/find-sdk-commit.sh" "${GIT_VER}" "${DEPS_DIR}")
echo "${SDK_OUTPUT}"

SDK_COMMIT=$(echo "${SDK_OUTPUT}" | grep "^SDK Commit:" | awk '{print $3}' | tr -d '\r' | xargs)
if [[ -z "${SDK_COMMIT}" ]]; then
  err "Failed to resolve SDK commit for Git version ${GIT_VER}."
fi
log "Resolved SDK commit: ${SDK_COMMIT}"

# 3. Setup dependencies (git-sdk-64 & rsync)
log "Step 3: Setting up dependencies in ${DEPS_DIR}..."
bash "${SCRIPT_DIR}/setup-deps.sh" "${RSYNC_VER}" "${SDK_COMMIT}" "${DEPS_DIR}"

GIT_SDK_64="${DEPS_DIR}/git-sdk-64"
RSYNC_SRC="${DEPS_DIR}/rsync"

# 4. Compile rsync inside MSYS2 SDK environment
REPO_ROOT_UNIX="$(cygpath -u "${REPO_ROOT}")"
BUILD_PREFIX_UNIX="${REPO_ROOT_UNIX}/build/rsync"
RSYNC_SRC_UNIX="${REPO_ROOT_UNIX}/deps/rsync"
BUILD_SCRIPT_UNIX="${REPO_ROOT_UNIX}/scripts/build-rsync.sh"
PACKAGE_SCRIPT_UNIX="${REPO_ROOT_UNIX}/scripts/package-rsync.sh"

log "Step 4: Compiling rsync inside SDK environment..."
bash "${SCRIPT_DIR}/run-in-sdk.sh" \
  "BUILD_PREFIX='${BUILD_PREFIX_UNIX}' bash '${BUILD_SCRIPT_UNIX}' '${RSYNC_SRC_UNIX}' '${RSYNC_VER}'" \
  "${GIT_SDK_64}"

# 5. Generate versions metadata
log "Step 5: Generating RELEASE_VERSIONS.md..."
bash "${SCRIPT_DIR}/generate-versions-md.sh" "${GIT_VER}" "${RSYNC_SRC}" "${GIT_SDK_64}" "${REPO_ROOT}/RELEASE_VERSIONS.md"

# 6. Package rsync into dist/
ZIP_NAME="rsync-${RSYNC_VER}-for-git-${GIT_VER}-64-bit.zip"
ZIP_OUTPUT_UNIX="${REPO_ROOT_UNIX}/dist/${ZIP_NAME}"

log "Step 6: Packaging rsync and MSYS runtime dependencies..."
bash "${SCRIPT_DIR}/run-in-sdk.sh" \
  "bash '${PACKAGE_SCRIPT_UNIX}' '${BUILD_PREFIX_UNIX}' '${ZIP_OUTPUT_UNIX}'" \
  "${GIT_SDK_64}"

# 7. Final verification
log "Step 7: Verifying build..."
if [[ -f "${DIST_DIR}/${ZIP_NAME}" && -f "${DIST_DIR}/${ZIP_NAME}.sha256" ]]; then
  log "✓ Build and packaging successful!"
  log "Dist files created:"
  ls -lh "${DIST_DIR}/${ZIP_NAME}" "${DIST_DIR}/${ZIP_NAME}.sha256"
  echo ""
  log "Testing built rsync binary directly:"
  "${BUILD_PREFIX}/bin/rsync.exe" --version | head -n 2
else
  err "Packaging failed. Expected zip file not found in ${DIST_DIR}."
fi
