#!/bin/bash
#
# Build script for rsync within the MSYS2 (Git for Windows SDK) environment.
#
# Usage:
#   ./build-rsync.sh <rsync-source-directory> <expected-rsync-version>

set -euo pipefail

# Print an error message to STDERR and exit.
#
# Globals:
#   None
# Arguments:
#   Error message string.
# Returns:
#   None
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR: $*" >&2
  exit 1
}

# Log a message with timestamp.
log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

# Safely install packages with retry logic and lockfile cleanup.
install_packages() {
  local -a packages=("$@")
  local retry_count=0
  local max_retries=3

  while [[ $retry_count -lt $max_retries ]]; do
    # Remove any stale pacman lock
    if [[ -f "/var/lib/pacman/db.lck" ]]; then
      log "Removing stale pacman lock (attempt $((retry_count + 1)))..."
      rm -f /var/lib/pacman/db.lck
    fi

    log "Attempting to install packages: ${packages[*]}"
    if pacman -S --noconfirm "${packages[@]}"; then
      log "Packages installed successfully."
      return 0
    fi

    retry_count=$((retry_count + 1))
    if [[ $retry_count -lt $max_retries ]]; then
      log "Package installation failed, retrying in 5 seconds... (attempt $((retry_count + 1))/$max_retries)"
      sleep 5
    fi
  done

  err "Failed to install packages after $max_retries attempts: ${packages[*]}"
}

# Main function to orchestrate the build.
#
# Globals:
#   HOME, BUILD_PREFIX
# Arguments:
#   Path to the rsync source directory.
#   Expected rsync version.
# Returns:
#   None
main() {
  if [[ $# -ne 2 ]]; then
    err "Usage: ${0} <rsync-source-directory> <expected-rsync-version>"
  fi

  local -r rsync_src="$1"
  local -r expected_ver="$2"
  local -r build_prefix="${BUILD_PREFIX:-${HOME}/build/rsync}"

  log "Using build prefix: $build_prefix"
  log "Rsync source directory: $rsync_src"
  log "Expected version: $expected_ver"

  # Ensure build directory exists
  mkdir -p "$build_prefix"

  log "Step 1: Installing dependencies..."
  # Install required build tools and libraries.
  # Using arrays to avoid shell word-splitting issues.
  install_packages \
    pkg-config \
    openssl-devel \
    libxxhash-devel \
    libzstd-devel \
    liblz4-devel \
    make \
    gcc \
    awk

  log "Verifying liblz4 installation..."
  if ! pkg-config --cflags --libs liblz4 > /dev/null 2>&1; then
    err "liblz4 was not properly installed or pkg-config cannot find it!"
  fi

  log "Step 1.5: Verifying rsync version..."
  if [[ ! -f "${rsync_src}/version.h" ]]; then
    err "version.h not found in ${rsync_src}"
  fi

  local -r actual_ver=$(awk -F'"' '/RSYNC_VERSION/ {print $2}' "${rsync_src}/version.h")
  log "Actual version from version.h: ${actual_ver}"

  if [[ "${actual_ver}" != "${expected_ver}" ]]; then
    err "Version mismatch! Expected ${expected_ver} but found ${actual_ver} in version.h"
  fi

  log "Step 2: Configuring rsync..."
  if [[ ! -d "${rsync_src}" ]]; then
    err "Rsync source directory not found: ${rsync_src}"
  fi

  cd "${rsync_src}" || err "Failed to cd into ${rsync_src}"

  # Clean any previous build artifacts
  if [[ -f "Makefile" ]]; then
    log "Cleaning previous build artifacts..."
    make distclean || true
  fi

  ./configure \
    --prefix="${build_prefix}" \
    --disable-acl-support \
    --disable-xattr-support \
    --disable-md2man

  log "Step 3: Building rsync..."
  make -j "$(nproc)"

  log "Step 4: Installing rsync..."
  make install

  log "Step 5: Validation..."
  if [[ ! -f "${build_prefix}/bin/rsync.exe" ]]; then
    err "rsync.exe was not installed at ${build_prefix}/bin/rsync.exe"
  fi

  log "Checking dynamic dependencies of rsync.exe:"
  if ldd "${build_prefix}/bin/rsync.exe" | grep -q msys-2.0.dll; then
    log "✓ msys-2.0.dll found in dependencies (correct)"
  else
    log "⚠ Warning: msys-2.0.dll not found in ldd output!"
    log "Full ldd output:"
    ldd "${build_prefix}/bin/rsync.exe"
  fi

  log "Running rsync --version:"
  if ! "${build_prefix}/bin/rsync.exe" --version; then
    err "Failed to execute rsync --version"
  fi

  log "Build and installation complete!"
  log "Binary location: ${build_prefix}/bin/rsync.exe"
}

main "$@"
