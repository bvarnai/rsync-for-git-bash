#!/bin/bash
#
# Execute a command inside the git-sdk-64 MSYS2 environment.
#
# This script standardizes the invocation of msys2_shell.cmd, managing path
# translations and argument conversion exclusions (MSYS2_ARG_CONV_EXCL) for both
# local Git Bash execution and GitHub Actions runners.
#
# Usage:
#   ./run-in-sdk.sh <command-string> [sdk-dir]
#
# Examples:
#   ./run-in-sdk.sh "gcc --version"
#   ./run-in-sdk.sh "bash /c/path/to/script.sh"

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <command-string> [sdk-dir]" >&2
  exit 1
fi

readonly CMD_TO_RUN="$1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)"

if [[ $# -ge 2 && -n "$2" ]]; then
  readonly SDK_ROOT="$(realpath "$2")"
elif [[ -d "${REPO_ROOT}/deps/git-sdk-64" ]]; then
  readonly SDK_ROOT="${REPO_ROOT}/deps/git-sdk-64"
else
  echo "Error: git-sdk-64 directory not found. Run scripts/setup-deps.sh first." >&2
  exit 1
fi

if [[ ! -f "${SDK_ROOT}/msys2_shell.cmd" ]]; then
  echo "Error: msys2_shell.cmd not found in ${SDK_ROOT}" >&2
  exit 1
fi

(
  cd "${SDK_ROOT}"
  MSYS2_ARG_CONV_EXCL="*" ./msys2_shell.cmd -msys -defterm -no-start -here -c "${CMD_TO_RUN}"
)
