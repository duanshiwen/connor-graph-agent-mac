#!/usr/bin/env bash
set -euo pipefail

# Xcode build phases use a minimal PATH that omits Homebrew.
for brew_dir in /opt/homebrew/bin /usr/local/bin; do
  [[ -d "$brew_dir" ]] && export PATH="$brew_dir:$PATH"
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/SearchKernel"
APP_BUNDLE=""
OUTPUT_DIR=""
CODESIGN_IDENTITY="${CONNOR_CODESIGN_IDENTITY:-}"
RUST_TARGET="${CONNOR_RUST_TARGET:-}"
RUST_TOOLCHAIN="${CONNOR_RUST_TOOLCHAIN:-}"
RUSTUP_BIN="${CONNOR_RUSTUP_BIN:-}"
RUN_TESTS=1
if [[ "${CONNOR_SEARCH_KERNEL_SKIP_TESTS:-0}" == "1" ]]; then
  RUN_TESTS=0
fi

usage() {
  cat <<'USAGE'
Usage: Scripts/package-search-kernel.sh [--app-bundle /path/Connor.app] [--output-dir /path/dir] [--codesign-identity IDENTITY] [--skip-tests]

Builds the embedded Rust/Tantivy Connor Memory SearchKernel and copies
libconnor_memory_search_kernel.dylib into a release-compatible location.

Options:
  --app-bundle PATH          Copy dylib to PATH/Contents/Frameworks.
  --output-dir PATH          Copy dylib to PATH.
  --codesign-identity ID     codesign the copied dylib with the given identity.
                             Defaults to CONNOR_CODESIGN_IDENTITY when set.
  --skip-tests               Skip cargo test before cargo build --release.

At least one of --app-bundle or --output-dir is required.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-bundle)
      APP_BUNDLE="${2:-}"; shift 2 ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"; shift 2 ;;
    --codesign-identity)
      CODESIGN_IDENTITY="${2:-}"; shift 2 ;;
    --skip-tests)
      RUN_TESTS=0; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

if [[ -z "$APP_BUNDLE" && -z "$OUTPUT_DIR" ]]; then
  usage >&2
  exit 2
fi

if [[ -n "$RUST_TARGET" && -z "$RUSTUP_BIN" ]]; then
  RUSTUP_BIN="$(command -v rustup || true)"
  if [[ -z "$RUSTUP_BIN" ]]; then
    for rustup_candidate in /opt/homebrew/opt/rustup/bin/rustup /usr/local/opt/rustup/bin/rustup; do
      if [[ -x "$rustup_candidate" ]]; then
        RUSTUP_BIN="$rustup_candidate"
        break
      fi
    done
  fi
fi
if [[ -n "$RUST_TARGET" && -n "$RUSTUP_BIN" && -z "$RUST_TOOLCHAIN" ]]; then
  RUST_TOOLCHAIN=stable
fi

if [[ -n "$RUST_TOOLCHAIN" && -n "$RUSTUP_BIN" ]]; then
  TOOLCHAIN_CARGO="$($RUSTUP_BIN which cargo --toolchain "$RUST_TOOLCHAIN")"
  TOOLCHAIN_RUSTC="$($RUSTUP_BIN which rustc --toolchain "$RUST_TOOLCHAIN")"
  CARGO_COMMAND=(env -u RUSTC_WRAPPER RUSTC="$TOOLCHAIN_RUSTC" "$TOOLCHAIN_CARGO")
else
  CARGO_COMMAND=(cargo)
fi

if ! command -v "${CARGO_COMMAND[0]}" >/dev/null 2>&1; then
  echo "error: cargo is required to build SearchKernel" >&2
  exit 127
fi

pushd "$KERNEL_DIR" >/dev/null
TARGET_ARGS=()
TARGET_OUTPUT_DIR="$KERNEL_DIR/target"
if [[ -n "$RUST_TARGET" ]]; then
  TARGET_ARGS=(--target "$RUST_TARGET")
  TARGET_OUTPUT_DIR="$TARGET_OUTPUT_DIR/$RUST_TARGET"
fi
if [[ "$RUN_TESTS" == "1" ]]; then
  "${CARGO_COMMAND[@]}" test "${TARGET_ARGS[@]}"
fi
"${CARGO_COMMAND[@]}" build --release "${TARGET_ARGS[@]}"
popd >/dev/null

CRATE_DYLIB="$TARGET_OUTPUT_DIR/release/libconnor_memory_search_kernel.dylib"

if [[ ! -f "$CRATE_DYLIB" ]]; then
  echo "error: expected dylib not found: $CRATE_DYLIB" >&2
  exit 1
fi

copy_and_sign() {
  local destination_dir="$1"
  mkdir -p "$destination_dir"
  local destination="$destination_dir/libconnor_memory_search_kernel.dylib"
  cp -f "$CRATE_DYLIB" "$destination"
  chmod 755 "$destination"
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$destination"
  fi
  /usr/bin/file "$destination"
  echo "$destination"
}

if [[ -n "$APP_BUNDLE" ]]; then
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: app bundle does not exist: $APP_BUNDLE" >&2
    exit 1
  fi
  copy_and_sign "$APP_BUNDLE/Contents/Frameworks"
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  copy_and_sign "$OUTPUT_DIR"
fi
