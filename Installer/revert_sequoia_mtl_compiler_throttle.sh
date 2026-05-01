#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: revert_sequoia_mtl_compiler_throttle.sh <mounted-system-volume> [backup-dir]

Restore the original Metal.framework binary and MTLCompilerService Info.plist
from the latest `Users/Shared/metal_patch_backup_*` backup on an offline Sequoia
system volume, refresh the target dyld shared cache, and create a new APFS root
snapshot.

If [backup-dir] is omitted, the newest matching backup directory on the target
volume is used automatically.

Run this against an offline Sequoia volume from a stable helper OS such as
Monterey or Big Sur.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
BACKUP_DIR="${2:-}"
TS="$(date +%Y%m%d-%H%M%S)"
MTL_BIN="${TARGET}/System/Library/Frameworks/Metal.framework/Versions/A/Metal"
MTL_XPC_PLIST="${TARGET}/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc/Contents/Info.plist"
BEFORE_REVERT_DIR="${TARGET}/Users/Shared/metal_patch_before_revert_${TS}"

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

metal_binary_has_throttle_patch() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys

path = sys.argv[1]
patch = bytes([0xB8, 0x02, 0x00, 0x00, 0x00, 0xC3, 0x90, 0x90])
targets = (0x2060, 0x2070, 0x2080)

try:
    with open(path, 'rb') as f:
        data = f.read()
except Exception:
    sys.exit(1)

sys.exit(0 if all(data[offset:offset + 8] == patch for offset in targets) else 1)
PY
}

latest_clean_backup_dir() {
  local root="$1"
  local -a matches ordered
  local dir
  setopt local_options null_glob
  matches=("${root}"/Users/Shared/metal_patch_backup_*)
  if [ "${#matches[@]}" -eq 0 ]; then
    return 0
  fi
  ordered=("${(@f)$(ls -1dt "${matches[@]}" 2>/dev/null)}")
  for dir in "${ordered[@]}"; do
    if [ -f "${dir}/Metal.binary.orig" ] && ! metal_binary_has_throttle_patch "${dir}/Metal.binary.orig"; then
      print -r -- "$dir"
      return 0
    fi
  done
}

remount_target_rw() {
  info "Attempting to remount target read/write..."
  if mount -uw "$TARGET" 2>/dev/null; then
    info "  remounted ${TARGET} read/write"
  else
    fail "could not remount ${TARGET} read/write"
  fi

  [ -w "$MTL_BIN" ] || fail "${MTL_BIN} is still not writable after remount"
}

backup_current_files() {
  mkdir -p "$BEFORE_REVERT_DIR"
  ditto "$MTL_BIN" "${BEFORE_REVERT_DIR}/Metal.binary.before-revert"
  ditto "$MTL_XPC_PLIST" "${BEFORE_REVERT_DIR}/MTLCompilerService_Info.plist.before-revert"
}

restore_file() {
  local src="$1"
  local dst="$2"
  [ -e "$src" ] || fail "missing backup item: $src"
  mkdir -p "$(dirname "$dst")"
  rm -f "$dst"
  ditto "$src" "$dst"
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
[ -f "$MTL_BIN" ] || fail "missing Metal binary: $MTL_BIN"
[ -f "$MTL_XPC_PLIST" ] || fail "missing MTLCompilerService Info.plist: $MTL_XPC_PLIST"

if [ -z "$BACKUP_DIR" ]; then
  BACKUP_DIR="$(latest_clean_backup_dir "$TARGET")"
fi

[ -n "$BACKUP_DIR" ] || fail "no clean metal_patch_backup_* directory found under ${TARGET}/Users/Shared"
require_dir "$BACKUP_DIR"
[ -f "${BACKUP_DIR}/Metal.binary.orig" ] || fail "backup is missing Metal.binary.orig: $BACKUP_DIR"
[ -f "${BACKUP_DIR}/MTLCompilerService_Info.plist.orig" ] || fail "backup is missing MTLCompilerService_Info.plist.orig: $BACKUP_DIR"
if metal_binary_has_throttle_patch "${BACKUP_DIR}/Metal.binary.orig"; then
  fail "selected backup already contains the Metal throttle patch: $BACKUP_DIR"
fi

info "Target root:  ${TARGET}"
info "Backup dir:   ${BACKUP_DIR}"
info "Stash broken: ${BEFORE_REVERT_DIR}"

remount_target_rw
backup_current_files

info
info "Restoring original Metal.framework payload..."
restore_file "${BACKUP_DIR}/Metal.binary.orig" "$MTL_BIN"
restore_file "${BACKUP_DIR}/MTLCompilerService_Info.plist.orig" "$MTL_XPC_PLIST"

refresh_dyld_shared_cache
create_root_snapshot

info
info "Metal compiler throttle reverted for ${TARGET}"
