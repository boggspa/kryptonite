#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_polaris_split_overlay.sh <mounted-system-volume> <polaris-stash-dir> [modern-oclp-payload-root]

Apply a split Polaris overlay onto an Intel-stable Sequoia root patch:
  - restore the known-working Polaris kernel-side kexts from the Sequoia stash
  - keep the newer OCLP 13.5.2 Polaris userland bundles that fixed login/session handoff

Defaults:
  modern-oclp-payload-root  /tmp/oclp-universal/13.5.2

Kernel-side items restored from stash:
  - AMDRadeonX4000.kext
  - AMDRadeonX4000HWServices.kext

Modern userland items restored from OCLP 13.5.2:
  - AMDMTLBronzeDriver.bundle
  - AMDRadeonVADriver2.bundle
  - AMDRadeonX4000GLDriver.bundle
  - AMDShared.bundle

Run this against an offline Sequoia volume from a stable boot OS such as Big Sur.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
STASH="${2%/}"
MODERN_PAYLOAD_ROOT="${3:-/tmp/oclp-universal/13.5.2}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-polaris-split-overlay"

typeset -a STASH_KERNEL_ITEMS
STASH_KERNEL_ITEMS=(
  "System/Library/Extensions/AMDRadeonX4000.kext"
  "System/Library/Extensions/AMDRadeonX4000HWServices.kext"
)

typeset -a MODERN_USERLAND_ITEMS
MODERN_USERLAND_ITEMS=(
  "System/Library/Extensions/AMDMTLBronzeDriver.bundle"
  "System/Library/Extensions/AMDRadeonVADriver2.bundle"
  "System/Library/Extensions/AMDRadeonX4000GLDriver.bundle"
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
  local source_root="$1"
  local rel="$2"
  local src="${source_root}/${rel}"
  local dst="${TARGET}/${rel}"
  local bkp="${BACKUP_ROOT}/${rel}"

  require_item "$source_root" "$rel"
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
  info "Stash kernel-side Polaris items:"
  for rel in "${STASH_KERNEL_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$STASH" "$rel")"
  done

  info "Modern OCLP Polaris userland items:"
  for rel in "${MODERN_USERLAND_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$MODERN_PAYLOAD_ROOT" "$rel")"
  done
}

require_dir "$TARGET"
require_dir "$STASH"
require_dir "$MODERN_PAYLOAD_ROOT"

for rel in "${STASH_KERNEL_ITEMS[@]}"; do
  require_item "$STASH" "$rel"
done

for rel in "${MODERN_USERLAND_ITEMS[@]}"; do
  require_item "$MODERN_PAYLOAD_ROOT" "$rel"
done

[ -e "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" ] || fail "target is missing AppleIntelFramebufferCapri.kext"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" ] || fail "target is missing AppleIntelHD4000Graphics.kext"

mkdir -p "$BACKUP_ROOT"

info "Target root:      ${TARGET}"
info "Polaris stash:    ${STASH}"
info "Modern payload:   ${MODERN_PAYLOAD_ROOT}"
info "Backup root:      ${BACKUP_ROOT}"
print_payload_state

remount_target_rw

info
info "Restoring stash kernel-side Polaris kexts..."
for rel in "${STASH_KERNEL_ITEMS[@]}"; do
  backup_and_replace "$STASH" "$rel"
  info "  restored ${rel}"
done

info
info "Restoring modern OCLP Polaris userland bundles..."
for rel in "${MODERN_USERLAND_ITEMS[@]}"; do
  backup_and_replace "$MODERN_PAYLOAD_ROOT" "$rel"
  info "  restored ${rel}"
done

rebuild_collections
create_root_snapshot

info
info "Split Polaris overlay complete."
