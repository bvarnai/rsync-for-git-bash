# <img src="assets/logo.png" height="38" alt="" align="absmiddle"> rsync-for-git-bash

Unmodified upstream builds of [`rsync`](https://rsync.samba.org/) linked against the `msys-2.0.dll` runtime used by each [Git for Windows](https://gitforwindows.org/) release.

## Problem

[Git for Windows](https://gitforwindows.org/) ships with its own MSYS2 runtime environment, including `msys-2.0.dll`. Standard `rsync` packages installed via `pacman` in a separate MSYS2 installation are built against a different, often newer, version of this runtime.

Because the MSYS2 runtime lacks Application Binary Interface (ABI) stability, running an `rsync.exe` built against a different runtime version inside Git Bash often fails with errors such as `ssh dup() in/out/err failed`. See [rsync-ssh-dll-mismatch.md](rsync-ssh-dll-mismatch.md) for details.

## Solution

This project resolves the compatibility mismatch by:
1. Identifying the exact `git-sdk-64` commit used to build a specific version of Git for Windows.
2. Building `rsync` from source within that SDK environment.
3. Packaging `rsync.exe` with the minimal set of required DLLs from the same SDK.

This keeps the binary compatible with the target Git for Windows runtime.

## Build configuration & disabled features

The following features are disabled during `./configure` because they are unsupported or unnecessary in Git for Windows:

| Feature flag              | Description                                                                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `--disable-acl-support`   | POSIX Access Control Lists (ACLs) do not map cleanly to Windows NTFS ACLs.                                           |
| `--disable-xattr-support` | Extended file attributes (`xattr`) are not consistently supported on Windows filesystems.                            |
| `--disable-idn`           | Disables Internationalized Domain Names (IDN) support to avoid extra external library dependencies.                  |
| `--disable-md2man`        | Skips generating man pages; Git for Windows does not include `man` by default.                                       |

## Versioning

Releases use a hybrid version string to identify both the `rsync` source version and the target Git for Windows release:

`rsync-<rsync_version>-for-git-<git_version>`

- **`<rsync_version>`**: Official `rsync` source version (e.g., `3.4.2`).
- **`<git_version>`**: Compatible Git for Windows version (e.g., `2.54.0.windows.1`).

Match the `rsync` build to your installed Git for Windows version.

### Scoop package versioning

Scoop requires monotonic numeric versions to detect upgrades across both upstreams. For the Scoop manifest in [`bvarnai/scoop-bucket`](https://github.com/bvarnai/scoop-bucket), the version is encoded as `<rsync_version>.<encoded_git_version>`:

- **Example:** `3.5.1.256002` (`rsync` `3.5.1` built against Git for Windows `2.56.0.windows.2`).
- The trailing digits encode the Git for Windows version (`<major><minor:2><patch:1><build:2>`), so Scoop triggers an update whenever either `rsync` or the Git SDK runtime baseline changes.

## Installation

### Scoop (recommended)

Install `rsync-for-git-bash` using [Scoop](https://scoop.sh/):

```powershell
# Add the bucket
scoop bucket add bvarnai-bucket https://github.com/bvarnai/scoop-bucket

# Install the package
scoop install bvarnai-bucket/rsync-for-git-bash
```

### Manual

1. Go to the project's **Releases** page.
2. Download the `.zip` archive matching your version of Git for Windows.
3. Extract the archive to a directory of your choice (e.g., `C:\tools\rsync-git-bash` or `~/rsync-git-bash` in Git Bash).
4. Add the `bin` subdirectory to your `PATH`:
   - **Git Bash:** Add `export PATH="$HOME/rsync-git-bash/bin:$PATH"` to `~/.bashrc`.
   - **Windows:** Add the absolute path to the `bin` folder to your Environment Variables.
5. Open a new Git Bash terminal and verify with `rsync --version`.

## Building from source

To reproduce a build locally on Windows, see [BUILDING.md](BUILDING.md).

---

## 🤖 AI Disclosure

![AI Assisted](https://img.shields.io/badge/AI-Assisted-blue?style=flat-square)

This project was developed with the assistance of AI tools. All AI-generated code has been reviewed, tested, and manually refined.
