# Building locally

This guide describes how to reproduce an `rsync-for-git-bash` build locally on Windows using the repository scripts.

## Prerequisites

- **OS:** 64-bit Windows
- **Shell:** Git Bash (do not use PowerShell or Command Prompt; scripts rely on `bash`, `cygpath`, `git`, `curl`, `awk`, and `sed`)
- **GitHub token (optional):** Export `GITHUB_TOKEN` or `GH_TOKEN` to avoid unauthenticated GitHub API rate limit:
  ```bash
  export GITHUB_TOKEN="<your-token>"
  ```

## Quick build

Run [scripts/build-local.sh](scripts/build-local.sh) from the repository root in Git Bash.

Build the latest upstream `rsync` and Git for Windows versions:

```bash
./scripts/build-local.sh
```

Reproduce a specific release by passing `<rsync-version>` and `<git-version>` (with or without a leading `v`):

```bash
./scripts/build-local.sh 3.5.1 2.56.0.windows.2
```

### Build outputs

A successful run produces:

| Path | Description |
| :--- | :--- |
| `build/rsync/bin/rsync.exe` | Compiled binary alongside its MSYS runtime DLLs |
| `dist/rsync-<rsync_version>-for-git-<git_version>-64-bit.zip` | Release archive containing `bin/`, `README.md`, `VERSIONS.md`, and `LICENSE` |
| `dist/rsync-<rsync_version>-for-git-<git_version>-64-bit.zip.sha256` | SHA-256 checksum for the archive |
| `RELEASE_VERSIONS.md` | Component version and commit metadata (packaged as `VERSIONS.md`) |

## Step-by-step pipeline

[scripts/build-local.sh](scripts/build-local.sh) orchestrates the same pipeline used by `.github/workflows/build-rsync.yml`. You can also run each stage individually from Git Bash:

1. **Resolve the `git-sdk-64` commit** matching the target Git for Windows release timestamp:
   ```bash
   ./scripts/find-sdk-commit.sh 2.56.0.windows.2 deps
   ```
   Note the `SDK Commit:` hash from the output.

2. **Fetch `git-sdk-64` and `rsync` sources** into `deps/`:
   ```bash
   ./scripts/setup-deps.sh 3.5.1 <sdk-commit> deps
   ```

3. **Compile `rsync` inside the SDK MSYS2 environment** (installs `gcc`, `make`, `pkg-config`, `openssl-devel`, `libxxhash-devel`, `libzstd-devel`, `liblz4-devel`, configures with `--disable-acl-support --disable-xattr-support --disable-idn --disable-md2man`, builds, and validates `ldd` + `rsync --version`):
   ```bash
   REPO_ROOT_UNIX="$(cygpath -u "$PWD")"
   ./scripts/run-in-sdk.sh \
     "BUILD_PREFIX='${REPO_ROOT_UNIX}/build/rsync' bash '${REPO_ROOT_UNIX}/scripts/build-rsync.sh' '${REPO_ROOT_UNIX}/deps/rsync' '3.5.1'" \
     deps/git-sdk-64
   ```

4. **Generate component metadata**:
   ```bash
   ./scripts/generate-versions-md.sh 2.56.0.windows.2 deps/rsync deps/git-sdk-64 RELEASE_VERSIONS.md
   ```

5. **Package the archive and SHA-256 checksum** (copies `rsync.exe` and all `/usr/*.dll` dependencies from `ldd` into `bin/`, plus `README.md`, `VERSIONS.md`, and `LICENSE`):
   ```bash
   mkdir -p dist
   ./scripts/run-in-sdk.sh \
     "bash '${REPO_ROOT_UNIX}/scripts/package-rsync.sh' '${REPO_ROOT_UNIX}/build/rsync' '${REPO_ROOT_UNIX}/dist/rsync-3.5.1-for-git-2.56.0.windows.2-64-bit.zip'" \
     deps/git-sdk-64
   ```

## Verification

Confirm the binary links against `msys-2.0.dll` and executes:

```bash
ldd build/rsync/bin/rsync.exe | grep msys-2.0.dll
./build/rsync/bin/rsync.exe --version
```

Verify the archive checksum and contents:

```bash
(cd dist && sha256sum -c rsync-3.5.1-for-git-2.56.0.windows.2-64-bit.zip.sha256)
unzip -l dist/rsync-3.5.1-for-git-2.56.0.windows.2-64-bit.zip
```

## Cleaning up

`deps/`, `build/`, `dist/`, and `RELEASE_VERSIONS.md` are git-ignored. Remove them to reset to a clean workspace:

```bash
rm -rf deps build dist RELEASE_VERSIONS.md
```
