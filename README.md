# rsync-for-git-bash

A specialized build of [`rsync`](https://rsync.samba.org/) linked against the specific `msys-2.0.dll` runtime used by a corresponding Git for Windows release.

## The Problem

Git for Windows ships with its own MSYS2 runtime environment, including a core `msys-2.0.dll`. Standard `rsync` packages installed via `pacman` in a separate MSYS2 installation are built against a different, often newer, version of this runtime.

Due to the lack of Application Binary Interface (ABI) stability in the MSYS2 runtime, attempting to run an `rsync.exe` built against a different runtime version inside Git Bash often results in cryptic errors. For a technical deep dive into these failures, such as the `ssh dup() in/out/err failed` error, see [rsync-ssh-dll-mismatch.md](rsync-ssh-dll-mismatch.md).

## The Solution

This project solves the compatibility problem by:
1. Identifying the exact `git-sdk-64` commit that was used to build a specific version of Git for Windows.
2. Building `rsync` from source within that precise SDK environment.
3. Packaging the resulting `rsync.exe` with the minimal set of required DLLs from that same SDK.

This ensures that the produced binary is perfectly compatible with the runtime environment of its target Git for Windows version.

## Build Configuration & Disabled Features

This build of `rsync` is configured to be a lean, compatible tool for the Git for Windows environment. Certain features that are not well-supported or are unnecessary in this context have been disabled during the `./configure` step.

| Feature Flag              | Description                                                                                                                                                             |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--disable-acl-support`   | POSIX Access Control Lists (ACLs) do not translate well to Windows NTFS ACLs and can cause unexpected behavior. This feature is disabled for simplicity and reliability. |
| `--disable-xattr-support` | Extended file attributes (`xattr`) are not commonly used or consistently supported on Windows filesystems. This is disabled to prevent compatibility issues.             |
| `--disable-md2man`        | Prevents the generation of man pages. Git for Windows does not include the `man` command by default. For documentation, please refer to the official rsync website. |

## Versioning

The releases use a hybrid versioning scheme to uniquely identify the build artifact and its compatibility:

`rsync-<rsync_version>-for-git-<git_version>`

-   **`<rsync_version>`**: The official version of the rsync source code (e.g., `3.4.2`).
-   **`<git_version>`**: The version of Git for Windows that this build is binary-compatible with (e.g., `2.54.0.windows.1`).

This allows you to easily match the `rsync` build to the specific version of Git for Windows you have installed.

## Usage

1.  Go to the project's **Releases** page.
2.  Download the `.zip` archive that matches your needs.
3.  Extract the archive. It will contain a `bin` directory.
4.  Copy the contents of the `bin` directory (`rsync.exe` and several `.dll` files) to a location in your `PATH` (e.g., `~/bin` or `/usr/local/bin` inside Git Bash).
5.  Ensure this location appears in your `PATH` before other Git directories. You can check with `echo $PATH`.
6.  Open a new Git Bash terminal and verify the installation with `rsync --version`.
