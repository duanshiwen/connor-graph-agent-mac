#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_DIR="$ROOT_DIR/.build/search-kernel-release"
KERNEL_DYLIB="$STAGING_DIR/libconnor_memory_search_kernel.dylib"
RUN_LIVE_VERIFY=1

usage() {
  cat <<'USAGE'
Usage: Scripts/verify-memory-os-release.sh [--skip-live-verify]

Runs the Connor Memory OS embedded graph/search release gate:
  1. Build/test/package Rust SearchKernel dylib.
  2. Run Swift tests covering SearchKernel FFI, search quality, graph CLI,
     Agent tool registration, and prompt contracts.
  3. Optionally run live search-index verify using the staged dylib.

USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-live-verify)
      RUN_LIVE_VERIFY=0; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

cd "$ROOT_DIR"

Scripts/package-search-kernel.sh --output-dir "$STAGING_DIR"

export CONNOR_MEMORY_SEARCH_KERNEL_DYLIB="$KERNEL_DYLIB"

swift test --filter MemoryOSSearchKernelFFITests
swift test --filter AppMemoryOSFacadeEmbeddedSearchTests
swift test --filter MemoryOSSearchQualityGoldenTests
swift test --filter AppMemoryOSCLIInspectorTests
swift test --filter AppMemoryOSSearchKernelFactoryTests
swift test --filter AppGraphAgentRuntimeFactoryLocalToolsTests
swift test --filter MemoryOSBackgroundPromptContractTests

if [[ "$RUN_LIVE_VERIFY" == "1" ]]; then
  swift run connor memory search-index verify
fi

echo "memory_os_release_gate ok"
