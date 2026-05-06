#!/bin/bash
#
# Package script for rsync within the MSYS2 (Git for Windows SDK) environment.
#
# Usage:
#   ./package-rsync.sh <rsync-install-prefix> <output-zip-path>

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

# Safely install a package with retry logic.
install_package() {
  local -r package="$1"
  local retry_count=0
  local max_retries=3

  while [[ $retry_count -lt $max_retries ]]; do
    # Remove any stale pacman lock
    if [[ -f "/var/lib/pacman/db.lck" ]]; then
      rm -f /var/lib/pacman/db.lck
    fi

    if pacman -S --noconfirm "$package"; then
      log "Package '$package' installed successfully."
      return 0
    fi

    retry_count=$((retry_count + 1))
    if [[ $retry_count -lt $max_retries ]]; then
      log "Failed to install '$package', retrying... (attempt $((retry_count + 1))/$max_retries)"
      sleep 5
    fi
  done

  err "Failed to install package '$package' after $max_retries attempts"
}

# Main function to orchestrate packaging.
#
# Globals:
#   None
# Arguments:
#   Path to the rsync installation prefix (e.g ~/build/rsync or absolute path).
#   Path where the final .zip file should be saved.
# Returns:
#   None
main() {
  if [[ $# -ne 2 ]]; then
    err "Usage: ${0} <rsync-install-prefix> <output-zip-path>"
  fi

  local -r install_prefix="$1"
  local -r output_zip="$2"
  local -r staging_dir="$(mktemp -d)"

  log "Install prefix: $install_prefix"
  log "Output zip: $output_zip"
  log "Staging directory: $staging_dir"

  # Trap to ensure cleanup on exit
  trap "rm -rf '$staging_dir'" EXIT

  # Ensure zip is installed in the MSYS2 environment
  if ! command -v zip &> /dev/null; then
    log "Installing zip package..."
    install_package zip
  fi

  # Ensure sha256sum is installed (provided by coreutils)
  if ! command -v sha256sum &> /dev/null; then
    log "Installing coreutils package for sha256sum..."
    install_package coreutils
  fi

  log "Step 1: Preparing staging directory..."
  # Package binaries into a flat 'bin' directory
  local -r bin_dir="${staging_dir}/bin"
  mkdir -p "${bin_dir}"

  if [[ ! -d "${install_prefix}" ]]; then
    err "Install prefix not found at ${install_prefix}"
  fi

  # Copy binaries from the install prefix
  if [[ ! -d "${install_prefix}/bin" ]]; then
    err "bin directory not found in install prefix: ${install_prefix}/bin"
  fi

  log "Copying binaries from ${install_prefix}/bin..."
  cp -rv "${install_prefix}/bin/"* "${bin_dir}/"

  local -r rsync_exe="${bin_dir}/rsync.exe"
  if [[ ! -f "${rsync_exe}" ]]; then
    err "rsync.exe not found at ${rsync_exe}"
  fi

  log "Step 2: Resolving MSYS DLL dependencies..."
  # We extract actual file paths from ldd output and filter for MSYS DLLs (located in /usr/...).
  # Windows system DLLs (C:\Windows) are inherently present on the target machine and ignored.
  
  # Use a temporary file to store ldd output for better diagnostics if it fails
  local -r ldd_output="$(mktemp)"
  if ! ldd "${rsync_exe}" > "${ldd_output}"; then
    cat "${ldd_output}" >&2
    err "ldd failed on ${rsync_exe}"
  fi

  local dll_count=0
  while IFS= read -r dll_path; do
    if [[ -n "${dll_path}" && -f "${dll_path}" ]]; then
      log "  -> Copying dependency: $(basename "${dll_path}")"
      # Use cp -v to see the copy action in the log.
      # We don't use -n here because we want to know if it fails, 
      # and in a fresh staging dir there should be no conflicts.
      cp -v "${dll_path}" "${bin_dir}/"
      ((dll_count++))
    fi
  done < <(grep -E '^/usr/.*\.dll$' "${ldd_output}" | awk '{print $3}' | sort -u)
  rm -f "${ldd_output}"

  log "Copied $dll_count MSYS DLL dependencies."

  log "Step 2.5: Copying readme and versions..."
  local -r script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  local -r project_root="$(dirname "${script_dir}")"

  local -a zip_files=("bin")

  if [[ -f "${project_root}/RELEASE_README.md" ]]; then
    cp "${project_root}/RELEASE_README.md" "${staging_dir}/README.md"
    zip_files+=("README.md")
  else
    log "Warning: RELEASE_README.md not found at ${project_root}/RELEASE_README.md"
  fi

  if [[ -f "${project_root}/RELEASE_VERSIONS.md" ]]; then
    cp "${project_root}/RELEASE_VERSIONS.md" "${staging_dir}/VERSIONS.md"
    zip_files+=("VERSIONS.md")
  else
    log "Warning: RELEASE_VERSIONS.md not found at ${project_root}/RELEASE_VERSIONS.md"
  fi

  log "Step 3: Creating ZIP archive..."
  cd "${staging_dir}"

  # Remove an existing zip file if it exists to ensure a clean package
  rm -f "${output_zip}"
  zip -r "${output_zip}" "${zip_files[@]}"

  log "Step 4: Generating SHA256 checksum..."
  # Run sha256sum from the directory where the zip was created to ensure the filename in the hash file is just the basename.
  (cd "$(dirname "${output_zip}")" && sha256sum "$(basename "${output_zip}")" > "$(basename "${output_zip}").sha256")

  log "Packaging complete! Archive created at ${output_zip}"
  log "Checksum file: ${output_zip}.sha256"
}

main "$@"
