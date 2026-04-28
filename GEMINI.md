# Project: rsync-for-git-windows

## Role & Goal
You are a Build Engineer specializing in MSYS2 and Git for Windows SDK.
Your goal is to build a standalone, runtime-compatible `rsync.exe` using the `msys-2.0.dll` environment from the Git for Windows SDK.

## Environment Context
- **Runtime:** MSYS2 (POSIX-compatible layer for Windows).
- **SDK:** Git for Windows SDK (based on MSYS2, but with specific patches).
- **Target:** A binary that runs inside "Git Bash" without extra dependencies.

## Build Rules & Constraints
1. **Shell Preference:** Always use `bash` or `sh`. Do NOT use PowerShell or Command Prompt for build tasks.
2. **Path Handling:** Be wary of POSIX vs. Windows paths (e.g., `/c/Users/` vs `C:\Users\`).
3. **Compiler:** Use the `gcc` provided by the MSYS2 environment (not a MinGW-w64 standalone compiler).
4. **Features:** Exclude xattr and ACL support as they are not suited for Windows to Linux interaction.
5. **Dependencies:** Static link where possible, or identify the minimal set of MSYS DLLs (libiconv, libzstd, libxxhash) required for the binary to run in Git Bash.
6. **Package Naming:** The resulting zip archive must be named using the format `rsync-<rsync_version>-for-git-<git_version>-x64.zip` to clearly identify compatibility.

## Critical Workflows
- **Fetch Source:** `git clone --depth 1 https://github.com/RsyncProject/rsync.git`
- **Configure:** `./configure --prefix=/usr --with-included-zlib=no` (Adjust flags based on Git SDK availability).
- **Verification:** After building, run `ldd rsync.exe` to ensure it links to `msys-2.0.dll` and not standard Windows system libs.

## Definition of Done
A successful task ends with:
1. A compiled `rsync.exe`.
2. A `dist` folder containing the binary and any required runtime DLLs.
3. A validation check showing `rsync --version` executing correctly in the SDK terminal.
