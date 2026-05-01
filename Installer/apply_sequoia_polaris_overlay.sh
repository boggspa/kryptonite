#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_polaris_overlay.sh <mounted-system-volume> <stash-dir>

Overlays a previously stashed OCLP Polaris payload onto an Intel-stable Sequoia
root patch, rebuilds kernel collections, and creates a new APFS root snapshot.

Run this against an offline Sequoia volume from a stable boot OS.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 2 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
STASH="${2%/}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-polaris-overlay"

typeset -a PAYLOAD_ITEMS
PAYLOAD_ITEMS=(
  "System/Library/Frameworks/OpenCL.framework"
  "System/Library/Frameworks/OpenGL.framework"
  "System/Library/Extensions/AMDMTLBronzeDriver.bundle"
  "System/Library/Extensions/AMDRadeonVADriver2.bundle"
  "System/Library/Extensions/AMDRadeonX4000.kext"
  "System/Library/Extensions/AMDRadeonX4000GLDriver.bundle"
  "System/Library/Extensions/AMDRadeonX4000HWServices.kext"
  "System/Library/Extensions/AMDShared.bundle"
)

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

kmutil_supports_flag() {
  local flag="$1"
  kmutil install --help 2>/dev/null | grep -q -- "$flag"
}

framework_binary_missing() {
  local root="$1"
  local framework_name="$2"
  local binary="${root}/System/Library/PrivateFrameworks/${framework_name}.framework/Versions/A/${framework_name}"
  [ ! -e "$binary" ]
}

remount_target_rw() {
  info "Attempting to remount target read/write..."
  if mount -uw "$TARGET" 2>/dev/null; then
    info "  remounted ${TARGET} read/write"
  else
    fail "could not remount ${TARGET} read/write"
  fi

  if [ ! -w "${TARGET}/System/Library/Extensions" ]; then
    fail "${TARGET}/System/Library/Extensions is still not writable after remount"
  fi
}

backup_and_replace() {
  local rel="$1"
  local src="${STASH}/${rel}"
  local dst="${TARGET}/${rel}"
  local bkp="${BACKUP_ROOT}/${rel}"

  [ -e "$src" ] || fail "missing stash payload item: $src"

  mkdir -p "$(dirname "$bkp")" "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    ditto "$dst" "$bkp"
    rm -rf "$dst"
  fi
  ditto "$src" "$dst"
}

rebuild_collections() {
  local -a cmd
  cmd=(
    kmutil install
    --volume-root "$TARGET"
    --update-all
    --force
    --variant-suffix release
  )

  if kmutil_supports_flag '--update-preboot'; then
    cmd+=(--update-preboot)
  fi

  if kmutil_supports_flag '--no-authorization'; then
    cmd+=(--no-authorization)
  fi

  if kmutil_supports_flag '--allow-missing-kdk'; then
    cmd+=(--allow-missing-kdk)
  fi

  info "Rebuilding target kernel collections..."
  printf '  %q' "${cmd[@]}"
  printf '\n'
  "${cmd[@]}"
}

create_root_snapshot() {
  info "Creating new APFS root snapshot for ${TARGET}..."
  bless --mount "$TARGET" --bootefi --create-snapshot
}

[ -d "$TARGET" ] || fail "missing target root: $TARGET"
[ -d "$STASH" ] || fail "missing stash directory: $STASH"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" ] || fail "target is missing AppleIntelFramebufferCapri.kext"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" ] || fail "target is missing AppleIntelHD4000Graphics.kext"
framework_binary_missing "$TARGET" "AppleGVA" && fail "target AppleGVA.framework is broken or missing"
framework_binary_missing "$TARGET" "AppleGVACore" && fail "target AppleGVACore.framework is broken or missing"

mkdir -p "$BACKUP_ROOT"

info "Target root: ${TARGET}"
info "Stash dir:   ${STASH}"
info "Backup dir:  ${BACKUP_ROOT}"

remount_target_rw

for rel in "${PAYLOAD_ITEMS[@]}"; do
  backup_and_replace "$rel"
  info "  restored ${rel}"
done

rebuild_collections
create_root_snapshot

info
info "Polaris overlay complete."
