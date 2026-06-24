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
