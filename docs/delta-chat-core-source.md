# Delta Chat Core Source Dependency

## Repository Boundary

TetiBot does not vendor Delta Chat Core, include it as a Cargo path dependency, or track it as a Git submodule. Core remains a separate checkout and is compiled into the `deltachat-rpc-server` executable. Teti starts that executable as a child process and communicates with it through JSON Lines over stdin/stdout.

Consequences:

- `git clone` of TetiBot does not download Core.
- Core source, Git history, build artifacts, and license files remain in the external Core checkout.
- Teti's repository must never commit a machine-specific Core path or the Core `target/` directory.
- Moving Core only requires changing `DELTA_CORE_DIR`; no Teti source edit or symlink is required.

## Reference Checkout

The implementation was developed and verified against:

```text
repository: https://github.com/chatmail/core.git
branch:     main
commit:     24848c0265485d9254b77010e54ba756428321da
package:    deltachat-rpc-server
Core API:   v2.51.0-dev at verification time
```

The commit is a reproducibility reference, not a submodule pin. Newer Core revisions may work, but changes to the JSON-RPC API should be tested before updating this reference.

## New Mac Setup

Install Xcode Command Line Tools and Rust, then keep the repositories in any directories you prefer:

```bash
xcode-select --install
rustup toolchain install stable
git clone https://github.com/chatmail/core.git /path/to/core
git clone <TetiBot repository URL> /path/to/TetiBot
```

For a reproducible Core build, check out the reference revision:

```bash
git -C /path/to/core checkout 24848c0265485d9254b77010e54ba756428321da
```

Build Core and Teti from the TetiBot repository root:

```bash
make chatmail-build DELTA_CORE_DIR=/path/to/core
```

Run the development application:

```bash
make chatmail-run DELTA_CORE_DIR=/path/to/core
```

When Core is a sibling of TetiBot named `core`, the default `DELTA_CORE_DIR=../core` works and the argument may be omitted.

## Path Resolution

At runtime Teti locates `deltachat-rpc-server` in this order:

1. Exact executable path in `DELTA_CHAT_RPC_SERVER`.
2. `$DELTA_CORE_DIR/target/release/deltachat-rpc-server`.
3. `../core/target/release/deltachat-rpc-server` relative to the launch directory.
4. `deltachat-rpc-server` found on `PATH`.

Examples:

```bash
DELTA_CORE_DIR=/Volumes/Code/core make chatmail-run

DELTA_CHAT_RPC_SERVER=/opt/deltachat/bin/deltachat-rpc-server \
  cargo run --manifest-path src-tauri/Cargo.toml
```

`DELTA_CHAT_RPC_SERVER` is useful for a prebuilt or packaged binary. For source builds on another Mac, prefer `DELTA_CORE_DIR` so the Make targets build the matching external checkout first.

## Verification

Show the external source path, current revision, and recommended revision:

```bash
make chatmail-core-revision DELTA_CORE_DIR=/path/to/core
```

Run Teti tests without modifying Core:

```bash
make chatmail-check
```

The Core account database is runtime data, not source. On macOS it is stored below Teti's application data directory and must not be copied into either Git repository.
