#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_offline_mtl_compiler_throttle.sh <mounted-system-volume>

Apply the existing Metal compiler throttle patch to an offline Sequoia system
volume, refresh the target dyld shared cache, and create a new APFS root
snapshot.

Use this only when:
  - the kryamdsurfguard baseline is already stable
  - kryrad24 has already been tested
  - Finder / Terminal / Spotlight still feel CPU-bound

Run this against an offline Sequoia volume from a stable helper OS such as
Monterey or Big Sur.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 1 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_SCRIPT="${SCRIPT_DIR}/patch_mtl_compiler_throttle.sh"

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

refresh_dyld_shared_cache() {
  local -a cmd
  cmd=(
    /usr/bin/update_dyld_shared_cache
    -root "$TARGET"
    -force
  )

  info
  info "Refreshing dyld shared cache for ${TARGET}:"
  printf '  %q' "${cmd[@]}"
  printf '\n'
  "${cmd[@]}"
}

create_root_snapshot() {
  info
  info "Creating new APFS root snapshot for ${TARGET}..."
  bless --mount "$TARGET" --bootefi --create-snapshot
}

require_dir "$TARGET"
[ "$TARGET" != "/" ] || fail "refusing to run against the active root volume; pass a mounted offline Sequoia system volume"
[ -e "${TARGET}/System/Library/Frameworks/Metal.framework/Versions/A/Metal" ] || fail "target is missing Metal.framework"
[ -f "$PATCH_SCRIPT" ] || fail "missing patch script: $PATCH_SCRIPT"

info "Target root: ${TARGET}"
info "Patch script: ${PATCH_SCRIPT}"
info
info "Applying offline MTLCompilerService throttle..."
bash "$PATCH_SCRIPT" "$TARGET"

refresh_dyld_shared_cache
create_root_snapshot

info
info "Offline Metal compiler throttle complete."
