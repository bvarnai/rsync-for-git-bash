# Analysis: "ssh dup() in/out/err failed" using rsync in Git Bash

## Overview

Running `rsync` over `ssh` in Git Bash (Git for Windows) or MSYS2 can fail at startup with `ssh dup() in/out/err failed`.

This is not a network or SSH configuration error. It is a process initialization failure caused by a **shared memory and file descriptor (FD) translation mismatch** between conflicting versions of `msys-2.0.dll`.

## Execution context

When you run `rsync -avz -e ssh ./local user@remote:/target`, the process tree is:

1. `rsync.exe` (parent process): initializes pipes for inter-process communication (IPC).
2. `ssh.exe` (child process): spawned by `rsync` (typically via `execvp` or `posix_spawnp`) to establish the transport layer.

In a native POSIX environment (like Linux), the parent process creates pipes and the forked child inherits standard file descriptors (`stdin`, `stdout`, `stderr`) directly.

## Root cause: MSYS2/Cygwin emulation constraints

Windows does not natively support the POSIX `fork()` model or POSIX file descriptors. Environments like Git Bash rely on `msys-2.0.dll` to emulate them.

### 1. File descriptor inheritance in MSYS

MSYS emulates POSIX pipes using underlying Windows handles. `msys-2.0.dll` maps each Windows handle back to a POSIX file descriptor (e.g., `fd 0`, `fd 1`, `fd 2`).

When `rsync` spawns `ssh`, it passes these Windows handles to the child process, which must translate them back into POSIX FDs.

### 2. The `dup()` system call

During initialization, `ssh` maps the inherited IPC pipes to its standard streams using `dup2()` or `dup()`, allowing `rsync` to write to `stdout` and `ssh` to read from `stdin`.

### 3. Path hazard (DLL mismatch)

The `dup()` failure occurs when the parent and child processes load different versions of `msys-2.0.dll`. This typically happens when `PATH` exposes multiple MSYS distributions.

**Example scenario:**

| Component   | Discovered path                        | Linked runtime          |
| ----------- | -------------------------------------- | ----------------------- |
| `rsync.exe` | `C:\msys64\usr\bin\rsync.exe`          | `msys-2.0.dll` (v3.4.1) |
| `ssh.exe`   | `C:\Program Files\Git\usr\bin\ssh.exe` | `msys-2.0.dll` (v3.3.5) |

If `rsync.exe` runs from a standalone MSYS2 installation, it initializes a shared memory region using the schema of its `msys-2.0.dll`. When it spawns `ssh.exe`, the OS loader resolves `ssh.exe` dependencies via `PATH`; if `PATH` points to Git for Windows, `ssh.exe` loads a different build of `msys-2.0.dll`.

### Mechanism of failure

1. `rsync` (DLL version A) passes Windows pipe handles to `ssh`.
2. `ssh` (DLL version B) attaches to the MSYS shared memory region created by `rsync`.
3. Because the shared memory schema differs between versions, `ssh` cannot interpret the internal PID map or FD translation table.
4. When `ssh` calls `dup()` to assign the inherited handles to `in/out/err` (`0`, `1`, `2`), the translation fails because the internal structures are invalid under DLL version B.
5. `dup()` returns `-1`, triggering `ssh dup() in/out/err failed`, and the IPC handshake hangs or aborts.

### Resolution

Every process in the execution tree must load binary-compatible `msys-2.0.dll` builds. They do not need to be the same physical file on disk, but their internal data structures and shared memory schemas must match (in practice, identical builds).
