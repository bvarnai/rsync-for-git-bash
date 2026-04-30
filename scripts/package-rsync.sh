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
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
  exit 1
}

# Main function to orchestrate packaging.
#
# Globals:
#   None
# Arguments:
#   Path to the rsync installation prefix (e.g. ~/build/rsync).
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

  # Ensure zip is installed in the MSYS2 environment
  if ! command -v zip &> /dev/null; then
    echo "Installing zip package..."
    pacman -S --noconfirm zip
  fi

  # Ensure sha256sum is installed (provided by coreutils)
  if ! command -v sha256sum &> /dev/null; then
    echo "Installing coreutils package for sha256sum..."
    pacman -S --noconfirm coreutils
  fi

  echo "Step 1: Preparing staging directory..."
  # Package binaries into a flat 'bin' directory
  local -r bin_dir="${staging_dir}/bin"
  mkdir -p "${bin_dir}"

  if [[ ! -d "${install_prefix}" ]]; then
    err "Install prefix not found at ${install_prefix}"
  fi

  # Copy binaries from the install prefix
  if [[ -d "${install_prefix}/bin" ]]; then
    cp -r "${install_prefix}/bin/"* "${bin_dir}/"
  else
    err "bin directory not found in install prefix: ${install_prefix}/bin"
  fi

  local -r rsync_exe="${bin_dir}/rsync.exe"
  if [[ ! -f "${rsync_exe}" ]]; then
    err "rsync.exe not found at ${rsync_exe}"
  fi

  echo "Step 2: Resolving MSYS DLL dependencies..."
  # We extract actual file paths from ldd output and filter for MSYS DLLs (located in /usr/...).
  # Windows system DLLs (C:\Windows) are inherently present on the target machine and ignored.
  while IFS= read -r dll_path; do
    if [[ -n "${dll_path}" && -f "${dll_path}" ]]; then
      echo "  -> Copying dependency: $(basename "${dll_path}")"
      # Use cp -n to avoid overwriting existing files just in case
      cp -n "${dll_path}" "${bin_dir}/"
    fi
  done < <(ldd "${rsync_exe}" | awk '{print $3}' | grep -E '^/usr/.*\.dll$')

  echo "Step 2.5: Copying readme and versions..."
  local -r script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
  local -r project_root="$(dirname "${script_dir}")"

  local -a zip_files=("bin")

  if [[ -f "${project_root}/RELEASE_README.md" ]]; then
    cp "${project_root}/RELEASE_README.md" "${staging_dir}/README.md"
    zip_files+=("README.md")
  else
    echo "Warning: RELEASE_README.md not found at ${project_root}/RELEASE_README.md"
  fi

  if [[ -f "${project_root}/RELEASE_VERSIONS.md" ]]; then
    cp "${project_root}/RELEASE_VERSIONS.md" "${staging_dir}/VERSIONS.md"
    zip_files+=("VERSIONS.md")
  else
    echo "Warning: RELEASE_VERSIONS.md not found at ${project_root}/RELEASE_VERSIONS.md"
  fi

  echo "Step 3: Creating ZIP archive..."
  cd "${staging_dir}"

  # Remove an existing zip file if it exists to ensure a clean package
  rm -f "${output_zip}"
  zip -r "${output_zip}" "${zip_files[@]}"

  echo "Step 4: Generating SHA256 checksum..."
  # Run sha256sum from the directory where the zip was created to ensure the filename in the hash file is just the basename.
  (cd "$(dirname "${output_zip}")" && sha256sum "$(basename "${output_zip}")" > "$(basename "${output_zip}").sha256")

  echo "Cleaning up staging directory..."
  cd - > /dev/null
  rm -rf "${staging_dir}"

  echo "Packaging complete! Archive created at ${output_zip}"
}

main "$@"