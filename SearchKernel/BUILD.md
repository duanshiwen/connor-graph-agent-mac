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
