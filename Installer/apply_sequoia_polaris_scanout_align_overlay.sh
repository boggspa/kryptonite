#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_polaris_scanout_align_overlay.sh <mounted-system-volume> [bronze-compat-payload-root] [amdshared-compat-payload-root] [aligned-polaris-payload-root]

Apply a targeted Polaris scanout-alignment overlay onto an Intel-stable Sequoia
root patch:
  - keep the proven non-BMI Bronze Metal bundle
  - keep the proven non-BMI AMDShared compiler/runtime bundle
  - align the remaining Polaris scanout-side stack to the 13.5.2 / 4.1.4 family

Defaults:
  bronze-compat-payload-root   /tmp/oclp-universal/12.5-23
  amdshared-compat-payload-root /tmp/oclp-universal/12.5
  aligned-polaris-payload-root /tmp/oclp-universal/13.5.2

This intentionally updates only these items:
  Compat items:
    - AMDMTLBronzeDriver.bundle
    - AMDShared.bundle
  Aligned 4.1.4 items:
    - AMDSupport.kext
    - AMD10000Controller.kext
    - AMD9500Controller.kext
    - AMDFramebuffer.kext
    - AMDRadeonVADriver2.bundle
    - AMDRadeonX4000GLDriver.bundle

It leaves the currently-working AuxKC accelerator stack untouched:
  - AMDRadeonX4000.kext
  - AMDRadeonX4000HWServices.kext

Use this when:
  - eGPU attach is stable
  - no new WindowServer / MTLCompilerService crashes occur
  - but external scanout is corrupted, tiled, or color-skewed

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
ALIGNED_PAYLOAD_ROOT="${4:-/tmp/oclp-universal/13.5.2}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-polaris-scanout-align-overlay"

typeset -a BRONZE_COMPAT_ITEMS
BRONZE_COMPAT_ITEMS=(
  "System/Library/Extensions/AMDMTLBronzeDriver.bundle"
)

typeset -a AMDSHARED_COMPAT_ITEMS
AMDSHARED_COMPAT_ITEMS=(
  "System/Library/Extensions/AMDShared.bundle"
)

typeset -a ALIGNED_ITEMS
ALIGNED_ITEMS=(
  "System/Library/Extensions/AMDSupport.kext"
  "System/Library/Extensions/AMD10000Controller.kext"
  "System/Library/Extensions/AMD9500Controller.kext"
  "System/Library/Extensions/AMDFramebuffer.kext"
  "System/Library/Extensions/AMDRadeonVADriver2.bundle"
  "System/Library/Extensions/AMDRadeonX4000GLDriver.bundle"
)

typeset -a INTEL_AUX_STAGE_ITEMS
INTEL_AUX_STAGE_ITEMS=(
  "Library/Extensions/AppleIntelFramebufferCapri.kext"
  "Library/Extensions/AppleIntelHD4000Graphics.kext"
)

typeset -a INTEL_SYSTEM_ITEMS
INTEL_SYSTEM_ITEMS=(
  "System/Library/Extensions/AppleIntelFramebufferCapri.kext"
  "System/Library/Extensions/AppleIntelHD4000Graphics.kext"
)

typeset -a AUX_STASH_ITEM_NAMES
AUX_STASH_ITEM_NAMES=(
  "AppleIntelFramebufferCapri.kext"
  "AppleIntelHD4000Graphics.kext"
  "AMDRadeonX4000.kext"
  "AMDRadeonX4000HWServices.kext"
  "AMDRadeonX4000HWLibs.kext"
  "AMDRadeonX4100HWLibs.kext"
  "AMDRadeonX4200HWLibs.kext"
  "AMDRadeonX4400HWLibs.kext"
  "AMDRadeonX4700HWLibs.kext"
)

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

normalize_bundle_ownership() {
  local bundle="$1"
  /usr/sbin/chown -R 0:0 "$bundle"
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

normalize_stashed_aux_ownership() {
  local stash_root="${TARGET}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions"
  local found_any=0

  info
  info "Normalizing stashed Auxiliary ownership..."

  if [ ! -d "$stash_root" ]; then
    info "  skipped missing ${stash_root}"
    return
  fi

  for name in "${AUX_STASH_ITEM_NAMES[@]}"; do
    for bundle in "${stash_root}"/*/"${name}"; do
      [ -d "$bundle" ] || continue
      normalize_bundle_ownership "$bundle"
      info "  normalized ${bundle}"
      found_any=1
    done
  done

  if [ "$found_any" -eq 0 ]; then
    info "  no matching stashed Auxiliary bundles found"
  fi
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

  info "Aligned 4.1.4 Polaris source:"
  for rel in "${ALIGNED_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$ALIGNED_PAYLOAD_ROOT" "$rel")"
  done
}

require_dir "$TARGET"
require_dir "$BRONZE_COMPAT_ROOT"
require_dir "$AMDSHARED_COMPAT_ROOT"
require_dir "$ALIGNED_PAYLOAD_ROOT"

for rel in "${BRONZE_COMPAT_ITEMS[@]}"; do
  require_item "$BRONZE_COMPAT_ROOT" "$rel"
done

for rel in "${AMDSHARED_COMPAT_ITEMS[@]}"; do
  require_item "$AMDSHARED_COMPAT_ROOT" "$rel"
done

for rel in "${ALIGNED_ITEMS[@]}"; do
  require_item "$ALIGNED_PAYLOAD_ROOT" "$rel"
done

[ -e "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" ] || fail "target is missing AppleIntelFramebufferCapri.kext"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" ] || fail "target is missing AppleIntelHD4000Graphics.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext" ] || fail "target is missing AMDRadeonX4000.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext" ] || fail "target is missing AMDRadeonX4000HWServices.kext"

mkdir -p "$BACKUP_ROOT"

info "Target root:             ${TARGET}"
info "Compat Bronze source:    ${BRONZE_COMPAT_ROOT}"
info "Compat AMDShared source: ${AMDSHARED_COMPAT_ROOT}"
info "Aligned payload source:  ${ALIGNED_PAYLOAD_ROOT}"
info "Backup root:             ${BACKUP_ROOT}"
print_payload_state

remount_target_rw

info
info "Restoring compat Bronze Metal bundle..."
for rel in "${BRONZE_COMPAT_ITEMS[@]}"; do
  backup_and_replace "$BRONZE_COMPAT_ROOT" "$rel"
  normalize_bundle_ownership "${TARGET}/${rel}"
  info "  restored ${rel}"
done

info
info "Restoring compat AMDShared bundle..."
for rel in "${AMDSHARED_COMPAT_ITEMS[@]}"; do
  backup_and_replace "$AMDSHARED_COMPAT_ROOT" "$rel"
  normalize_bundle_ownership "${TARGET}/${rel}"
  info "  restored ${rel}"
done

info
info "Restoring aligned 4.1.4 Polaris scanout-side items..."
for rel in "${ALIGNED_ITEMS[@]}"; do
  backup_and_replace "$ALIGNED_PAYLOAD_ROOT" "$rel"
  normalize_bundle_ownership "${TARGET}/${rel}"
  info "  restored ${rel}"
done

info
info "Normalizing system Ivy Bridge Intel ownership..."
for rel in "${INTEL_SYSTEM_ITEMS[@]}"; do
  if [ -e "${TARGET}/${rel}" ]; then
    normalize_bundle_ownership "${TARGET}/${rel}"
    info "  normalized ${rel}"
  else
    info "  skipped missing ${rel}"
  fi
done

info
info "Normalizing staged Ivy Bridge Auxiliary items..."
for rel in "${INTEL_AUX_STAGE_ITEMS[@]}"; do
  if [ -e "${TARGET}/${rel}" ]; then
    normalize_bundle_ownership "${TARGET}/${rel}"
    info "  normalized ${rel}"
  else
    info "  skipped missing ${rel}"
  fi
done

rebuild_collections
normalize_stashed_aux_ownership
create_root_snapshot

info
info "Polaris scanout alignment overlay complete."
