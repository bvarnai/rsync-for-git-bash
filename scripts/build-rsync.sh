#!/bin/bash
#
# Build script for rsync within the MSYS2 (Git for Windows SDK) environment.
#
# Usage:
#   ./build-rsync.sh <rsync-source-directory>

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
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
  exit 1
}

# Main function to orchestrate the build.
#
# Globals:
#   HOME
# Arguments:
#   Path to the rsync source directory.
# Returns:
#   None
main() {
  if [[ $# -ne 2 ]]; then
    err "Usage: ${0} <rsync-source-directory> <expected-rsync-version>"
  fi

  local -r rsync_src="$1"
  local -r expected_ver="$2"

  echo "Step 1: Installing dependencies..."
  # Update package databases and install requested packages.
  pacman -Sy --noconfirm pkg-config openssl-devel libxxhash-devel \
    libzstd-devel liblz4-devel make gcc awk

  echo "Verifying liblz4 installation..."
  if ! pkg-config --cflags --libs liblz4; then
    err "liblz4 was not properly installed or pkg-config cannot find it!"
  fi

  echo "Step 1.5: Verifying rsync version..."
  local -r actual_ver=$(awk -F'"' '/RSYNC_VERSION/ {print $2}' "${rsync_src}/version.h")
  echo "Expected version: ${expected_ver}"
  echo "Actual version:   ${actual_ver}"

  if [[ "${actual_ver}" != "${expected_ver}" ]]; then
    err "Version mismatch! Expected ${expected_ver} but found ${actual_ver} in version.h"
  fi

  echo "Step 2: Configuring rsync..."
  cd "${rsync_src}" || err "Failed to cd into ${rsync_src}"

  ./configure \
    --prefix="${HOME}/build/rsync" \
    --disable-acl-support  \
    --disable-xattr-support  \
    --disable-md2man

  echo "Step 3: Building rsync..."
  make

  echo "Step 4: Installing rsync..."
  make install

  echo "Step 5: Validation..."
  echo "Checking dynamic dependencies of rsync.exe:"
  if ! ldd rsync.exe | grep -q msys-2.0.dll; then
    echo "Warning: msys-2.0.dll not found in ldd output!" >&2
  fi

  echo "Running rsync --version:"
  "${HOME}/build/rsync/bin/rsync.exe" --version

  echo "Build and installation complete!"
}

main "$@"