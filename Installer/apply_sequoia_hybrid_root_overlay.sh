#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_hybrid_root_overlay.sh <target-root> [intel-source-root] [gva-source-root]

Repair a Polaris-patched Sequoia volume by restoring the missing Ivy Bridge
kernel pieces and the torn-down AppleGVA binaries that OCLP removed when it
switched the root patch set to AMD Polaris only.

Defaults:
  intel-source-root  /Volumes/BigSur
  gva-source-root    /Volumes/Monterey

Environment:
  HYBRID_SYNC_INTEL_BUNDLES=1  Also overwrite the Intel companion bundles.
  HYBRID_REBUILD_KC=1          Run kmutil install --update-all after copying.

Recommended flow:
  1. Let OCLP apply the Polaris root patch.
  2. Boot a stable OS with the Sequoia target mounted offline.
  3. Run this script with sudo against the mounted Sequoia system volume.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
INTEL_SOURCE="${2:-/Volumes/BigSur}"
GVA_SOURCE="${3:-/Volumes/Monterey}"

PATCHSET_PLIST="${TARGET}/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-hybrid-overlay"

typeset -a INTEL_REQUIRED_ITEMS
INTEL_REQUIRED_ITEMS=(
  "System/Library/Extensions/AppleIntelFramebufferCapri.kext"
  "System/Library/Extensions/AppleIntelHD4000Graphics.kext"
)

typeset -a INTEL_OPTIONAL_ITEMS
INTEL_OPTIONAL_ITEMS=(
  "System/Library/Extensions/AppleIntelGraphicsShared.bundle"
  "System/Library/Extensions/AppleIntelHD4000GraphicsGLDriver.bundle"
  "System/Library/Extensions/AppleIntelHD4000GraphicsMTLDriver.bundle"
  "System/Library/Extensions/AppleIntelHD4000GraphicsVADriver.bundle"
  "System/Library/Extensions/AppleIntelIVBVA.bundle"
)

typeset -a GVA_ITEMS
GVA_ITEMS=(
  "System/Library/PrivateFrameworks/AppleGVA.framework"
  "System/Library/PrivateFrameworks/AppleGVACore.framework"
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

set_osbundle_required() {
  local plist="$1"
  local value="$2"

  if /usr/libexec/PlistBuddy -c "Print :OSBundleRequired" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :OSBundleRequired $value" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :OSBundleRequired string $value" "$plist"
  fi
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

require_framework_binary() {
  local root="$1"
  local framework_name="$2"
  local binary="${root}/System/Library/PrivateFrameworks/${framework_name}.framework/Versions/A/${framework_name}"
  [ -e "$binary" ] || fail "missing source framework binary: ${binary}"
}

framework_binary_missing() {
  local root="$1"
  local framework_name="$2"
  local binary="${root}/System/Library/PrivateFrameworks/${framework_name}.framework/Versions/A/${framework_name}"
  [ ! -e "$binary" ]
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

backup_and_replace() {
  local source_root="$1"
  local rel="$2"
  local source="${source_root}/${rel}"
  local target="${TARGET}/${rel}"
  local backup="${BACKUP_ROOT}/${rel}"

  require_item "$source_root" "$rel"
  mkdir -p "$(dirname "$backup")" "$(dirname "$target")"

  if [ -e "$target" ] || [ -L "$target" ]; then
    ditto "$target" "$backup"
    rm -rf "$target"
  fi

  ditto "$source" "$target"
}

enable_intel_auxkc_support() {
  local capri_plist="${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext/Contents/Info.plist"
  local hd4000_plist="${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext/Contents/Info.plist"

  set_osbundle_required "$capri_plist" "Auxiliary"
  set_osbundle_required "$hd4000_plist" "Auxiliary"
}

print_current_state() {
  info "Current target state:"
  for rel in "${INTEL_REQUIRED_ITEMS[@]}"; do
    if [ -e "${TARGET}/${rel}" ]; then
      info "  present ${rel}$(bundle_version_summary "$TARGET" "$rel")"
    else
      info "  missing ${rel}"
    fi
  done

  for name in AppleGVA AppleGVACore; do
    if framework_binary_missing "$TARGET" "$name"; then
      info "  broken /System/Library/PrivateFrameworks/${name}.framework (binary missing)"
    else
      info "  present /System/Library/PrivateFrameworks/${name}.framework"
    fi
  done
}

print_post_state() {
  info
  info "Post-overlay target state:"
  for rel in "${INTEL_REQUIRED_ITEMS[@]}"; do
    if [ -e "${TARGET}/${rel}" ]; then
      info "  present ${rel}$(bundle_version_summary "$TARGET" "$rel")"
    else
      info "  still missing ${rel}"
    fi
  done

  for name in AppleGVA AppleGVACore; do
    if framework_binary_missing "$TARGET" "$name"; then
      info "  still broken /System/Library/PrivateFrameworks/${name}.framework"
    else
      info "  present /System/Library/PrivateFrameworks/${name}.framework"
    fi
  done
}

remount_target_rw() {
  info
  info "Attempting to remount target read/write..."
  if mount -uw "$TARGET" 2>/dev/null; then
    info "  remounted ${TARGET} read/write"
  else
    fail "could not remount ${TARGET} read/write. If this is an offline APFS system volume, make sure it is mounted locally and not via file sharing."
  fi

  if [ ! -w "${TARGET}/System/Library/Extensions" ]; then
    fail "${TARGET}/System/Library/Extensions is still not writable after remount"
  fi
}

rebuild_collections() {
  local -a cmd
  local kdk=""

  if [ -d "${TARGET}/Library/Developer/KDKs" ]; then
    kdk="$(find "${TARGET}/Library/Developer/KDKs" -maxdepth 1 -type d -name 'KDK_*' | sort | tail -1)"
  fi

  cmd=(
    kmutil install
    --volume-root "$TARGET"
    --update-all
    --force
    --variant-suffix release
  )

  if kmutil_supports_flag '--allow-missing-kdk'; then
    cmd+=(--allow-missing-kdk)
  fi

  if kmutil_supports_flag '--update-preboot'; then
    cmd+=(--update-preboot)
  fi

  if kmutil_supports_flag '--no-authorization'; then
    cmd+=(--no-authorization)
  fi

  if [ -n "$kdk" ] && kmutil_supports_flag '--kdk'; then
    cmd+=(--kdk "$kdk")
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

require_dir "$TARGET"
require_dir "$INTEL_SOURCE"
require_dir "$GVA_SOURCE"
require_dir "${TARGET}/System/Library/Extensions"
require_dir "${TARGET}/System/Library/PrivateFrameworks"

for rel in "${INTEL_REQUIRED_ITEMS[@]}"; do
  require_item "$INTEL_SOURCE" "$rel"
done

for rel in "${GVA_ITEMS[@]}"; do
  require_item "$GVA_SOURCE" "$rel"
done
require_framework_binary "$GVA_SOURCE" "AppleGVA"
require_framework_binary "$GVA_SOURCE" "AppleGVACore"

mkdir -p "$BACKUP_ROOT"

if [ -f "$PATCHSET_PLIST" ]; then
  info "Detected OCLP patch manifest at ${PATCHSET_PLIST}"
  if plutil -p "$PATCHSET_PLIST" 2>/dev/null | grep -q '"AMD Polaris"'; then
    info "  patch manifest currently includes AMD Polaris"
  fi
  if plutil -p "$PATCHSET_PLIST" 2>/dev/null | grep -q '"Intel Ivy Bridge"'; then
    info "  patch manifest currently includes Intel Ivy Bridge"
  else
    info "  patch manifest currently does not include Intel Ivy Bridge"
  fi
fi

info
info "Target root:      ${TARGET}"
info "Intel source:     ${INTEL_SOURCE}"
info "GVA source:       ${GVA_SOURCE}"
info "Backup root:      ${BACKUP_ROOT}"
print_current_state
remount_target_rw

info
info "Restoring missing Ivy Bridge kexts..."
for rel in "${INTEL_REQUIRED_ITEMS[@]}"; do
  backup_and_replace "$INTEL_SOURCE" "$rel"
  info "  restored ${rel}"
done

info
info "Enabling Ivy Bridge AuxKC support..."
enable_intel_auxkc_support
info "  set AppleIntelFramebufferCapri.kext OSBundleRequired=Auxiliary"
info "  set AppleIntelHD4000Graphics.kext OSBundleRequired=Auxiliary"

if [ "${HYBRID_SYNC_INTEL_BUNDLES:-0}" = "1" ]; then
  info
  info "Synchronising Ivy Bridge companion bundles..."
  for rel in "${INTEL_OPTIONAL_ITEMS[@]}"; do
    require_item "$INTEL_SOURCE" "$rel"
    backup_and_replace "$INTEL_SOURCE" "$rel"
    info "  synced ${rel}"
  done
else
  info
  info "Leaving existing Ivy Bridge companion bundles in place."
fi

info
info "Restoring AppleGVA binaries/frameworks..."
for rel in "${GVA_ITEMS[@]}"; do
  backup_and_replace "$GVA_SOURCE" "$rel"
  info "  restored ${rel}"
done

print_post_state

if [ "${HYBRID_REBUILD_KC:-0}" = "1" ]; then
  rebuild_collections
else
  info
  info "Kernel collections were not rebuilt."
  info "To rebuild them on the target volume, rerun with:"
  info "  HYBRID_REBUILD_KC=1 sudo $0 '${TARGET}' '${INTEL_SOURCE}' '${GVA_SOURCE}'"
fi

create_root_snapshot

info
info "Hybrid root overlay complete."
