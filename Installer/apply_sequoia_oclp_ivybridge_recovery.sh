#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_oclp_ivybridge_recovery.sh <target-root> [oclp-payload-root]

Restore the exact Ivy Bridge + AppleGVA payload that OCLP ships for Sequoia
hybrid recovery. This avoids mixing local Big Sur Intel components with the
newer 11.7.10 payload inside OCLP's Universal-Binaries image.

Defaults:
  oclp-payload-root  /tmp/oclp-universal/11.7.10

Typical flow:
  1. Mount OCLP's Universal-Binaries.dmg.
  2. Run this script from a stable OS against the mounted Sequoia volume.
  3. Reboot Sequoia with no eGPU connected first.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
PAYLOAD_ROOT="${2:-/tmp/oclp-universal/11.7.10}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="${SCRIPT_DIR}/apply_sequoia_hybrid_root_overlay.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_dir() {
  local path="$1"
  [ -d "$path" ] || fail "missing directory: $path"
}

require_item() {
  local root="$1"
  local rel="$2"
  [ -e "${root}/${rel}" ] || fail "missing payload item: ${root}/${rel}"
}

require_dir "$TARGET"
require_dir "$PAYLOAD_ROOT"
[ -f "$HELPER" ] || fail "missing helper script: $HELPER"

require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelFramebufferCapri.kext"
require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelHD4000Graphics.kext"
require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelGraphicsShared.bundle"
require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelHD4000GraphicsGLDriver.bundle"
require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelHD4000GraphicsMTLDriver.bundle"
require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelHD4000GraphicsVADriver.bundle"
require_item "$PAYLOAD_ROOT" "System/Library/Extensions/AppleIntelIVBVA.bundle"
require_item "$PAYLOAD_ROOT" "System/Library/PrivateFrameworks/AppleGVA.framework"
require_item "$PAYLOAD_ROOT" "System/Library/PrivateFrameworks/AppleGVACore.framework"

printf '%s\n' "Using OCLP payload root: ${PAYLOAD_ROOT}"
printf '%s\n' "Applying exact Ivy Bridge + GVA recovery payload to: ${TARGET}"

HYBRID_SYNC_INTEL_BUNDLES=1 \
HYBRID_REBUILD_KC=1 \
exec zsh "$HELPER" "$TARGET" "$PAYLOAD_ROOT" "$PAYLOAD_ROOT"
