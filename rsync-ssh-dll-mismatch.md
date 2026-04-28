## Analysis: "ssh dup() in/out/err failed" using Rsync in Git Bash

### Overview

When executing `rsync` over `ssh` within Git Bash (Git for Windows) or MSYS2 environments, users may encounter a fatal initialization error: `ssh dup() in/out/err failed`.

This error is not a network failure or a standard SSH misconfiguration. Instead, it is a low-level process initialization failure caused by **Shared Memory and File Descriptor (FD) translation mismatch** resulting from conflicting versions of the MSYS POSIX emulation layer (`msys-2.0.dll`).

### Execution Context

To understand the failure, it is necessary to examine the process execution tree. When you run a command like `rsync -avz -e ssh ./local user@remote:/target`, the execution flow is:

1. `rsync.exe` (Parent Process): Initializes and prepares pipes for Inter-Process Communication (IPC).
2. `ssh.exe` (Child Process): Spawned by `rsync` (typically via `execvp` or `posix_spawnp`) to establish the transport layer.

In a native POSIX environment (like Linux), the parent process creates pipes and standard file descriptors (`stdin`, `stdout`, `stderr`) are cleanly inherited by the forked child process.

### The Root Cause: MSYS2/Cygwin Emulation Constraints

Windows does not natively support the POSIX `fork()` model or POSIX file descriptors. Environments like Git Bash rely on `msys-2.0.dll` to emulate these constructs.

#### 1. File Descriptor Inheritance in MSYS
MSYS emulates POSIX pipes using underlying Windows handles. The translation logic that maps a Windows handle back to a POSIX file descriptor (e.g., `fd 0`, `fd 1`, `fd 2`) is managed internally by `msys-2.0.dll`.

When `rsync` spawns `ssh`, it passes these Windows handles to the child process. The child process must then translate them back into POSIX FDs.

#### 2. The `dup()` System Call

During initialization, the child process (`ssh`) attempts to map the inherited IPC pipes to its standard streams using the `dup2()` or `dup()` system calls. This allows `rsync` to write to its `stdout` and have `ssh` read it seamlessly from its `stdin`.

#### 3. The Pathing Hazard (DLL Mismatch)

The `dup()` failure occurs when the system attempts to load two different versions of `msys-2.0.dll` across the parent-child boundary. This is common in environments where the user's `PATH` variable exposes multiple MSYS distributions.

**Example Scenario:**
| Component | Discovered Path | Linked Runtime |
|-----------|-----------------|----------------|
| `rsync.exe` | `C:\msys64\usr\bin\rsync.exe` | `msys-2.0.dll` (v3.4.1) |
| `ssh.exe`   | `C:\Program Files\Git\usr\bin\ssh.exe` | `msys-2.0.dll` (v3.3.5)|

If `rsync.exe` is executed from a standalone MSYS2 installation, it initializes a shared memory region according to the schema of its specific `msys-2.0.dll`.

When it executes `ssh.exe`, the OS loader resolves dependencies for `ssh.exe`. If the `PATH` directs it to the Git for Windows installation, `ssh.exe` loads a different build of `msys-2.0.dll`.

#### Mechanism of Failure

1. `rsync` (DLL version A) passes Windows pipe handles to `ssh`.
2. `ssh` (DLL version B) attempts to attach to the MSYS shared memory region created by `rsync`.
3. Due to the version mismatch, the shared memory schema differs. `ssh` cannot correctly interpret the internal PID map or the FD translation table.
4. When `ssh` attempts to invoke `dup()` to assign the inherited handles to `in/out/err` (0, 1, and 2), the translation fails because the underlying internal structures are unrecognizable or malformed in the context of DLL version B.
5. `dup()` returns -1, triggering the fatal `ssh dup() in/out/err failed` error, and the IPC handshake hangs or aborts.

#### Resolution

To resolve this issue, the architectural constraint of MSYS must be satisfied: The `msys-2.0.dll` files loaded by all processes in the execution tree must be binary compatible. They do not strictly need to be the exact same physical file on disk, but their internal data structures and shared memory schemas must perfectly align (which practically means they are identical builds).
