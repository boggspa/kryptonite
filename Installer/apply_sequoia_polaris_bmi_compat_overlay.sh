#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_polaris_bmi_compat_overlay.sh <mounted-system-volume> [bronze-compat-payload-root] [amdshared-compat-payload-root] [modern-polaris-payload-root]

Apply a targeted Polaris userland compatibility overlay onto an Intel-stable
Sequoia root patch:
  - restore the newest locally-available pre-BMI Bronze Metal bundle
  - restore an older pre-BMI AMDShared compiler/runtime bundle
  - keep the remaining Polaris userland pieces on the newer 13.5.2 payload

Defaults:
  bronze-compat-payload-root    /tmp/oclp-universal/12.5-23
  amdshared-compat-payload-root /tmp/oclp-universal/12.5
  modern-polaris-payload-root   /tmp/oclp-universal/13.5.2

This intentionally updates only these userland items:
  Compat items:
    - AMDMTLBronzeDriver.bundle        (from 12.5-23 / 4.0.8)
    - AMDShared.bundle                 (from 12.5 / 0.0.0)
  Modern items:
    - AMDRadeonVADriver2.bundle        (from 13.5.2 / 4.1.4)
    - AMDRadeonX4000GLDriver.bundle    (from 13.5.2 / 4.1.4)

It leaves the currently-working AuxKC Polaris kernel-side stack untouched:
  - AMDRadeonX4000.kext
  - AMDRadeonX4000HWServices.kext

Use this when Sequoia is already loading the Polaris AuxKC stack, but eGPU
attach still crashes in:
  - AMDMTLBronzeDriverOld.dylib
  - AMDShared.bundle/Contents/PlugIns/libAMDIL902.dylib

Run this against an offline Sequoia volume from a stable boot OS such as Big Sur.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 4 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
BRONZE_COMPAT_ROOT="${2:-/tmp/oclp-universal/12.5-23}"
AMDSHARED_COMPAT_ROOT="${3:-/tmp/oclp-universal/12.5}"
MODERN_PAYLOAD_ROOT="${4:-/tmp/oclp-universal/13.5.2}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-polaris-bmi-compat-overlay"

typeset -a BRONZE_COMPAT_ITEMS
BRONZE_COMPAT_ITEMS=(
  "System/Library/Extensions/AMDMTLBronzeDriver.bundle"
)

typeset -a AMDSHARED_COMPAT_ITEMS
AMDSHARED_COMPAT_ITEMS=(
  "System/Library/Extensions/AMDShared.bundle"
)

typeset -a MODERN_ITEMS
MODERN_ITEMS=(
  "System/Library/Extensions/AMDRadeonVADriver2.bundle"
  "System/Library/Extensions/AMDRadeonX4000GLDriver.bundle"
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
  info "Compat Bronze source:"
  for rel in "${BRONZE_COMPAT_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$BRONZE_COMPAT_ROOT" "$rel")"
  done

  info "Compat AMDShared source:"
  for rel in "${AMDSHARED_COMPAT_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$AMDSHARED_COMPAT_ROOT" "$rel")"
  done

  info "Modern Polaris userland source:"
  for rel in "${MODERN_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$MODERN_PAYLOAD_ROOT" "$rel")"
  done
}

require_dir "$TARGET"
require_dir "$BRONZE_COMPAT_ROOT"
require_dir "$AMDSHARED_COMPAT_ROOT"
require_dir "$MODERN_PAYLOAD_ROOT"

for rel in "${BRONZE_COMPAT_ITEMS[@]}"; do
  require_item "$BRONZE_COMPAT_ROOT" "$rel"
done

for rel in "${AMDSHARED_COMPAT_ITEMS[@]}"; do
  require_item "$AMDSHARED_COMPAT_ROOT" "$rel"
done

for rel in "${MODERN_ITEMS[@]}"; do
  require_item "$MODERN_PAYLOAD_ROOT" "$rel"
done

[ -e "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" ] || fail "target is missing AppleIntelFramebufferCapri.kext"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" ] || fail "target is missing AppleIntelHD4000Graphics.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext" ] || fail "target is missing AMDRadeonX4000.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext" ] || fail "target is missing AMDRadeonX4000HWServices.kext"

mkdir -p "$BACKUP_ROOT"

info "Target root:             ${TARGET}"
info "Compat Bronze source:    ${BRONZE_COMPAT_ROOT}"
info "Compat AMDShared source: ${AMDSHARED_COMPAT_ROOT}"
info "Modern payload:          ${MODERN_PAYLOAD_ROOT}"
info "Backup root:             ${BACKUP_ROOT}"
print_payload_state

remount_target_rw

info
info "Restoring compat Bronze Metal bundle..."
for rel in "${BRONZE_COMPAT_ITEMS[@]}"; do
  backup_and_replace "$BRONZE_COMPAT_ROOT" "$rel"
  info "  restored ${rel}"
done

info
info "Restoring compat AMDShared bundle..."
for rel in "${AMDSHARED_COMPAT_ITEMS[@]}"; do
  backup_and_replace "$AMDSHARED_COMPAT_ROOT" "$rel"
  info "  restored ${rel}"
done

info
info "Refreshing the remaining modern Polaris userland bundle set..."
for rel in "${MODERN_ITEMS[@]}"; do
  backup_and_replace "$MODERN_PAYLOAD_ROOT" "$rel"
  info "  restored ${rel}"
done

rebuild_collections
create_root_snapshot

info
info "Polaris BMI compatibility overlay complete."
