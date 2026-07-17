#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/ConnorGraphAgentMac.xcodeproj"
SCHEME="ConnorGraphAgentMacApp"
APP_NAME="康纳同学"
APP_BUNDLE_NAME="$APP_NAME.app"
BUILD_ROOT="${CONNOR_RELEASE_BUILD_DIR:-$ROOT_DIR/.build/macos-release}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
PRODUCT_DIR="$BUILD_ROOT/product"
DIST_DIR="${CONNOR_DIST_DIR:-$ROOT_DIR/dist}"
ARCH="${CONNOR_RELEASE_ARCH:-$(uname -m)}"
VERSION=""

usage() {
  cat <<'USAGE'
Usage: Scripts/package-macos-ad-hoc.sh [--arch ARCH] [--version VERSION] [--output-dir DIR]

Builds an architecture-specific Release app, applies an ad-hoc signature to
the app and all embedded Mach-O code, verifies the signature, and creates a DMG.

The resulting app is not notarized. On first launch, users must Control-click
the app, choose Open, and confirm Open once.

Options:
  --arch ARCH        arm64, x86_64, or all (default: current Mac).
  --version VERSION   Override the DMG version label.
  --output-dir DIR    Write the DMG to DIR (default: ./dist).
  --help, -h          Show this help.

Environment:
  CONNOR_RELEASE_ARCH       Build architecture (default: current Mac).
  CONNOR_RELEASE_BUILD_DIR  Temporary build directory.
  CONNOR_DIST_DIR           Output directory, overridden by --output-dir.
  CONNOR_RELEASE_REUSE_BUILD  Set to 1 to keep DerivedData for an incremental rebuild.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output-dir)
      DIST_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$ARCH" in
  arm64|x86_64|all) ;;
  *)
    echo "error: unsupported architecture: $ARCH" >&2
    exit 2
    ;;
esac

if [[ "$ARCH" == "all" ]]; then
  child_args=(--output-dir "$DIST_DIR")
  if [[ -n "$VERSION" ]]; then
    child_args+=(--version "$VERSION")
  fi
  "$0" --arch arm64 "${child_args[@]}"
  "$0" --arch x86_64 "${child_args[@]}"
  exit 0
fi

case "$ARCH" in
  arm64) RUST_TARGET="aarch64-apple-darwin" ;;
  x86_64) RUST_TARGET="x86_64-apple-darwin" ;;
esac

for command_name in xcodebuild cargo codesign hdiutil ditto; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command not found: $command_name" >&2
    exit 127
  fi
done

RUSTUP_BIN="${CONNOR_RUSTUP_BIN:-$(command -v rustup || true)}"
if [[ -z "$RUSTUP_BIN" ]]; then
  for rustup_candidate in /opt/homebrew/opt/rustup/bin/rustup /usr/local/opt/rustup/bin/rustup; do
    if [[ -x "$rustup_candidate" ]]; then
      RUSTUP_BIN="$rustup_candidate"
      break
    fi
  done
fi
if [[ -z "$RUSTUP_BIN" ]]; then
  echo "error: rustup is required for architecture-specific release builds" >&2
  exit 127
fi

mkdir -p "$BUILD_ROOT" "$DIST_DIR"
BUILD_ROOT="$BUILD_ROOT/$ARCH"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
PRODUCT_DIR="$BUILD_ROOT/product"
mkdir -p "$BUILD_ROOT"
if [[ "${CONNOR_RELEASE_REUSE_BUILD:-0}" != "1" ]]; then
  rm -rf "$DERIVED_DATA"
fi
rm -rf "$PRODUCT_DIR"
mkdir -p "$PRODUCT_DIR"

RUST_TARGET_LIBDIR="$("$RUSTUP_BIN" run stable rustc --print target-libdir --target "$RUST_TARGET" 2>/dev/null || true)"
if [[ -z "$RUST_TARGET_LIBDIR" || ! -d "$RUST_TARGET_LIBDIR" ]]; then
  echo "error: Rust target is not installed: $RUST_TARGET" >&2
  echo "Install a rustup-managed toolchain and run: rustup target add $RUST_TARGET" >&2
  exit 1
fi

echo "Building $APP_NAME ($ARCH, Release)..."
CONNOR_RUST_TARGET="$RUST_TARGET" \
CONNOR_RUST_TOOLCHAIN=stable \
CONNOR_RUSTUP_BIN="$RUSTUP_BIN" \
CONNOR_SEARCH_KERNEL_SKIP_TESTS=1 \
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS,arch=$ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_BUNDLE_NAME"
APP_PATH="$PRODUCT_DIR/$APP_BUNDLE_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: built app not found: $BUILT_APP" >&2
  exit 1
fi

ditto "$BUILT_APP" "$APP_PATH"

echo "Applying ad-hoc signatures to embedded code..."
while IFS= read -r -d '' candidate; do
  if [[ "$candidate" == "$APP_PATH/Contents/MacOS/"* ]]; then
    continue
  fi
  if /usr/bin/file -b "$candidate" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign - --timestamp=none --options runtime "$candidate"
  fi
done < <(find "$APP_PATH/Contents" -type f -print0)

# Seal nested bundles after their executables, deepest paths first.
while IFS= read -r nested_bundle; do
  [[ -n "$nested_bundle" ]] || continue
  codesign --force --sign - --timestamp=none --options runtime "$nested_bundle"
done < <(
  find "$APP_PATH/Contents" -type d \( \
    -name '*.app' -o -name '*.appex' -o -name '*.framework' -o \
    -name '*.xpc' -o -name '*.bundle' \
  \) -print | awk '{ print length($0), $0 }' | sort -rn | cut -d' ' -f2-
)

# Sign top-level executables only after all nested code has a valid signature.
while IFS= read -r -d '' executable; do
  if /usr/bin/file -b "$executable" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign - --timestamp=none --options runtime "$executable"
  fi
done < <(find "$APP_PATH/Contents/MacOS" -type f -print0)

codesign \
  --force \
  --sign - \
  --timestamp=none \
  --options runtime \
  --entitlements "$ROOT_DIR/ConnorGraphAgentMac.entitlements" \
  "$APP_PATH"

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
fi

SAFE_VERSION="${VERSION//[^A-Za-z0-9._-]/-}"
DMG_NAME="Connor-$SAFE_VERSION-macOS-$ARCH.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_ROOT="$(mktemp -d "$BUILD_ROOT/dmg.XXXXXX")"
trap 'rm -rf "$DMG_ROOT"' EXIT

ditto "$APP_PATH" "$DMG_ROOT/$APP_BUNDLE_NAME"
ln -s /Applications "$DMG_ROOT/Applications"
printf '%s\n' \
  '首次安装：' \
  '1. 将“康纳同学”拖入 Applications 文件夹。' \
  '2. 在“应用程序”中按住 Control 点击“康纳同学”，选择“打开”。' \
  '3. 在系统提示中再次点击“打开”。以后可直接双击运行。' \
  '' \
  '本版本使用 Ad-hoc 签名，未经过 Apple 公证。无需运行终端命令。' \
  > "$DMG_ROOT/首次打开说明.txt"

rm -f "$DMG_PATH"
echo "Creating $DMG_NAME..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

echo
echo "Package created: $DMG_PATH"
echo "Architecture: $ARCH"
echo "Signing: ad-hoc (not notarized)"
echo "Expected first launch: Control-click > Open > Open"
