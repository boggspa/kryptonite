#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_oclp_polaris_modern_overlay.sh <mounted-system-volume> [oclp-payload-root]

Overlay a newer OCLP Polaris userland payload onto an Intel-stable Sequoia root
patch, rebuild kernel collections, and create a new APFS root snapshot.

Defaults:
  oclp-payload-root  /tmp/oclp-universal/13.5.2

This intentionally updates only the AMD Polaris userland stack:
  - AMDMTLBronzeDriver.bundle
  - AMDRadeonVADriver2.bundle
  - AMDRadeonX4000.kext
  - AMDRadeonX4000GLDriver.bundle
  - AMDRadeonX4000HWServices.kext
  - AMDShared.bundle

It leaves the now-working Ivy Bridge / Intel OCLP root patch in place.
Run this against an offline Sequoia volume from a stable boot OS.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
PAYLOAD_ROOT="${2:-/tmp/oclp-universal/13.5.2}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-oclp-polaris-modern-overlay"

typeset -a POLARIS_ITEMS
POLARIS_ITEMS=(
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

require_dir() {
  local path="$1"
  [ -d "$path" ] || fail "missing directory: $path"
}

require_item() {
  local root="$1"
  local rel="$2"
  [ -e "${root}/${rel}" ] || fail "missing source item: ${root}/${rel}"
}

kmutil_supports_flag() {
  local flag="$1"
  kmutil install --help 2>/dev/null | grep -q -- "$flag"
}

bundle_version_summary() {
  local root="$1"
  local rel="$2"
  local info_plist="${root}/${rel}/Contents/Info.plist"
  if [ -f "$info_plist" ]; then
    local short_ver bundle_ver
    short_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
    bundle_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)"
    printf ' (%s / %s)' "${short_ver:-?}" "${bundle_ver:-?}"
  fi
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
  local src="${PAYLOAD_ROOT}/${rel}"
  local dst="${TARGET}/${rel}"
  local bkp="${BACKUP_ROOT}/${rel}"

  require_item "$PAYLOAD_ROOT" "$rel"
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

  info
  info "Rebuilding target kernel collections:"
  printf '  %q' "${cmd[@]}"
  printf '\n'
  "${cmd[@]}"
}

create_root_snapshot() {
  info
  info "Creating new APFS root snapshot for ${TARGET}..."
  bless --mount "$TARGET" --bootefi --create-snapshot
}

print_payload_state() {
  info "Modern Polaris payload:"
  for rel in "${POLARIS_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$PAYLOAD_ROOT" "$rel")"
  done
}

require_dir "$TARGET"
require_dir "$PAYLOAD_ROOT"

for rel in "${POLARIS_ITEMS[@]}"; do
  require_item "$PAYLOAD_ROOT" "$rel"
done

[ -e "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" ] || fail "target is missing AppleIntelFramebufferCapri.kext"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" ] || fail "target is missing AppleIntelHD4000Graphics.kext"

mkdir -p "$BACKUP_ROOT"

info "Target root:     ${TARGET}"
info "OCLP payload:    ${PAYLOAD_ROOT}"
info "Backup root:     ${BACKUP_ROOT}"
print_payload_state

remount_target_rw

info
info "Restoring newer OCLP Polaris userland stack..."
for rel in "${POLARIS_ITEMS[@]}"; do
  backup_and_replace "$rel"
  info "  restored ${rel}"
done

rebuild_collections
create_root_snapshot

info
info "Modern Polaris overlay complete."
