# SearchKernel Build

Authoritative timestamp for this setup pass: 2026-06-24 23:57 GMT+8.

## Toolchain

The local embedded Memory OS Search Kernel is built with the Rust toolchain.

Verified locally:

```text
cargo 1.96.0
rustc 1.96.0
```

Install on macOS with Homebrew when missing:

```bash
brew install rust
```

## Build and Test

From the repository root:

```bash
cd SearchKernel
cargo test
cargo build --release
```

The kernel is a local embedded library. It is not a server, daemon, HTTP sidecar, or CLI search service.

## Runtime Library Resolution

Connor resolves `libconnor_memory_search_kernel.dylib` in this order:

1. `CONNOR_MEMORY_SEARCH_KERNEL_DYLIB` environment override.
2. App bundle `Contents/Frameworks/libconnor_memory_search_kernel.dylib`.
3. App bundle `Contents/Resources/SearchKernel/libconnor_memory_search_kernel.dylib`.
4. Executable sibling `libconnor_memory_search_kernel.dylib`.
5. Development repository fallback: `SearchKernel/target/release/libconnor_memory_search_kernel.dylib`.

Release packaging should copy the release dylib into the app bundle, preferably under `Contents/Frameworks/`, so production does not depend on repository-relative paths or environment variables.

## Release Packaging Script

From the repository root, use the packaging helper to build, test, copy, and optionally sign the embedded dylib:

```bash
Scripts/package-search-kernel.sh --app-bundle /path/to/Connor.app
```

For CI or local release staging without an app bundle:

```bash
Scripts/package-search-kernel.sh --output-dir .build/search-kernel-release
```

For Developer ID / hardened runtime signing, pass an identity explicitly or via `CONNOR_CODESIGN_IDENTITY`:

```bash
CONNOR_CODESIGN_IDENTITY="Developer ID Application: Example Team" \
  Scripts/package-search-kernel.sh --app-bundle /path/to/Connor.app
```

The script performs:

1. `cargo test` unless `--skip-tests` is supplied.
2. `cargo build --release`.
3. Copy `SearchKernel/target/release/libconnor_memory_search_kernel.dylib` to either:
   - `Connor.app/Contents/Frameworks/libconnor_memory_search_kernel.dylib`, or
   - the supplied `--output-dir`.
4. `chmod 755` on the copied dylib.
5. Optional `codesign --force --timestamp --options runtime --sign <identity>` on the copied dylib.

This script intentionally packages the kernel as an in-process app library, not as a sidecar, daemon, server, or subprocess search service.
