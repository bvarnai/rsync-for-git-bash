#!/bin/bash
#
# Formats Scoop version from Rsync and Git for Windows versions or release tags.
#
# Encodes Git version into a numeric suffix to ensure monotonic updates in Scoop:
#   <rsync-version>.<encoded-git-version>
#   e.g. rsync-3.5.1-for-git-2.56.0.windows.2 -> 3.5.1.256002
#
# Usage:
#   ./scripts/format-scoop-version.sh <tag-name>
#   ./scripts/format-scoop-version.sh <rsync-ver> <git-ver>
#   ./scripts/format-scoop-version.sh --test

set -euo pipefail

encode_git_version() {
  local raw_git="$1"
  raw_git="${raw_git#v}"

  # Match: major.minor.patch with optional .windows.build
  # e.g. 2.56.0.windows.2 or 2.56.0.windows.1 or 2.56.0
  if [[ "$raw_git" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(\.windows\.([0-9]+))? ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local build="${BASH_REMATCH[5]:-1}" # Default to 1 if no .windows.X suffix

    # Format: Major, 2-digit Minor, 1-digit Patch, 2-digit Build
    printf "%d%02d%d%02d" "$major" "$minor" "$patch" "$build"
  else
    echo "Error: Unrecognized Git for Windows version format: '$raw_git'" >&2
    return 1
  fi
}

format_scoop_version() {
  local rsync_ver=""
  local git_ver=""

  if [[ $# -eq 1 ]]; then
    local tag="$1"
    # Tag format: rsync-<rsync-ver>-for-git-<git-ver>
    if [[ "$tag" =~ ^rsync-([0-9.]+)-for-git-(.+)$ ]]; then
      rsync_ver="${BASH_REMATCH[1]}"
      git_ver="${BASH_REMATCH[2]}"
    else
      echo "Error: Tag '$tag' does not match expected format 'rsync-<rsync-ver>-for-git-<git-ver>'" >&2
      return 1
    fi
  elif [[ $# -eq 2 ]]; then
    rsync_ver="${1#v}"
    git_ver="${2#v}"
  else
    echo "Usage: $0 <tag-name> OR $0 <rsync-ver> <git-ver> OR $0 --test" >&2
    return 1
  fi

  local encoded_git
  encoded_git="$(encode_git_version "$git_ver")"
  echo "${rsync_ver}.${encoded_git}"
}

run_tests() {
  local failures=0

  assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  PASS: $label -> $actual"
    else
      echo "  FAIL: $label: expected '$expected', got '$actual'" >&2
      failures=$((failures + 1))
    fi
  }

  echo "Running format-scoop-version self-tests..."

  # Historical releases
  assert_eq "rsync 3.5.1 with git 2.56.0.windows.2 (tag)" \
    "3.5.1.256002" "$(format_scoop_version "rsync-3.5.1-for-git-2.56.0.windows.2")"

  assert_eq "rsync 3.5.1 with git 2.56.0.windows.1 (tag)" \
    "3.5.1.256001" "$(format_scoop_version "rsync-3.5.1-for-git-2.56.0.windows.1")"

  assert_eq "rsync 3.5.0 with git 2.55.0.windows.5 (tag)" \
    "3.5.0.255005" "$(format_scoop_version "rsync-3.5.0-for-git-2.55.0.windows.5")"

  assert_eq "rsync 3.4.2 with git 2.54.0.windows.1 (tag)" \
    "3.4.2.254001" "$(format_scoop_version "rsync-3.4.2-for-git-2.54.0.windows.1")"

  # Two-argument invocation
  assert_eq "Two arguments (3.5.1, 2.56.0.windows.2)" \
    "3.5.1.256002" "$(format_scoop_version "3.5.1" "2.56.0.windows.2")"

  assert_eq "Arguments with v prefix (v3.5.1, v2.56.0.windows.2)" \
    "3.5.1.256002" "$(format_scoop_version "v3.5.1" "v2.56.0.windows.2")"

  # Edge case: git version without .windows.X suffix defaults build to 1 (01)
  assert_eq "Git version without .windows suffix (2.56.0)" \
    "3.5.1.256001" "$(format_scoop_version "3.5.1" "2.56.0")"

  # Edge case: patch number increment (e.g. 2.56.1.windows.2)
  assert_eq "Patch version increment (2.56.1.windows.2)" \
    "3.5.1.256102" "$(format_scoop_version "3.5.1" "2.56.1.windows.2")"

  if [[ $failures -eq 0 ]]; then
    echo "All tests passed successfully!"
    return 0
  else
    echo "Tests failed: $failures failure(s)" >&2
    return 1
  fi
}

if [[ "${1:-}" == "--test" ]]; then
  run_tests
else
  format_scoop_version "$@"
fi
