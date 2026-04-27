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
  if [[ $# -ne 1 ]]; then
    err "Usage: ${0} <rsync-source-directory>"
  fi

  local -r rsync_src="$1"

  echo "Step 1: Installing dependencies..."
  # Update package databases and install requested packages.
  pacman -Sy --noconfirm pkg-config openssl-devel libxxhash-devel \
    libzstd-devel liblz4-devel make gcc awk

  echo "Step 2: Configuring rsync..."
  cd "${rsync_src}" || err "Failed to cd into ${rsync_src}"

  ./configure \
    --prefix="${HOME}/dev/rsync" \
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
  "${HOME}/dev/rsync/bin/rsync.exe" --version

  echo "Build and installation complete!"
}

main "$@"