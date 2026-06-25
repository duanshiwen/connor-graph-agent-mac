#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/SearchKernel"
CRATE_DYLIB="$KERNEL_DIR/target/release/libconnor_memory_search_kernel.dylib"
APP_BUNDLE=""
OUTPUT_DIR=""
CODESIGN_IDENTITY="${CONNOR_CODESIGN_IDENTITY:-}"
RUN_TESTS=1

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

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build SearchKernel" >&2
  exit 127
fi

pushd "$KERNEL_DIR" >/dev/null
if [[ "$RUN_TESTS" == "1" ]]; then
  cargo test
fi
cargo build --release
popd >/dev/null

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
