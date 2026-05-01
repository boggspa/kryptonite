#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_offline_mtl_compiler_plist_only.sh <mounted-system-volume>

Apply only the MTLCompilerService plist throttle to an offline Sequoia system
volume. This keeps the Metal.framework binary untouched, resigns only the XPC
bundle, and creates a new APFS root snapshot.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 1 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_SCRIPT="${SCRIPT_DIR}/patch_mtl_compiler_throttle.sh"
MTL_XPC_PLIST="${TARGET}/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc/Contents/Info.plist"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

require_dir() {
  local path="$1"
  [ -d "$path" ] || fail "missing directory: $path"
}

create_root_snapshot() {
  info
  info "Creating new APFS root snapshot for ${TARGET}..."
  bless --mount "$TARGET" --bootefi --create-snapshot
}

require_dir "$TARGET"
[ "$TARGET" != "/" ] || fail "refusing to run against the active root volume; pass a mounted offline Sequoia system volume"
[ -f "$PATCH_SCRIPT" ] || fail "missing patch script: $PATCH_SCRIPT"
[ -f "$MTL_XPC_PLIST" ] || fail "missing MTLCompilerService Info.plist: $MTL_XPC_PLIST"

info "Target root: ${TARGET}"
info "Patch script: ${PATCH_SCRIPT}"
info
info "Applying offline MTLCompilerService plist-only throttle..."
KRY_MTL_PLIST_ONLY=1 bash "$PATCH_SCRIPT" "$TARGET"
create_root_snapshot

info
info "Offline MTLCompilerService plist-only throttle complete."
