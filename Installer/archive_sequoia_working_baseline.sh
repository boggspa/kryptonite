#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: archive_sequoia_working_baseline.sh <mounted-system-volume> <mounted-efi-root> [output-root]

Archive the current known-good Sequoia Ivy Bridge + Polaris working state into
one timestamped baseline folder.

This captures:
  - a live graphics probe bundle from the current booted system
  - the mounted OpenCore EFI used for that boot
  - the key Intel + Polaris system/library extension bundles
  - ownership, signature, bundle-version, and boot-args manifests
  - the self-contained validation helper folder used to reproduce the state

Run this while booted into the working Sequoia baseline, with the matching EFI
mounted and passed as <mounted-efi-root>.

Defaults:
  output-root  ~/Desktop
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
EFI_ROOT="${2%/}"
OUT_ROOT="${3:-${HOME}/Desktop}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE_SCRIPT="${SCRIPT_DIR}/collect_blank_panel_probe.sh"
if [ ! -f "${PROBE_SCRIPT}" ]; then
  PROBE_SCRIPT="${HOME}/Documents/kryptonite/Installer/collect_blank_panel_probe.sh"
fi
TS="$(date +%Y%m%d-%H%M%S)"
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
BASELINE_DIR="${OUT_ROOT%/}/Kryptonite-WorkingBaseline-${TS}-${OS_VER}-${BUILD_VER}"
PROBE_ROOT="${BASELINE_DIR}/probe"
EFI_ARCHIVE="${BASELINE_DIR}/efi"
SYSTEM_ARCHIVE="${BASELINE_DIR}/system-root"
HELPER_ARCHIVE="${BASELINE_DIR}/helper-scripts"
MANIFEST_DIR="${BASELINE_DIR}/manifests"

typeset -a SYSTEM_ITEMS
SYSTEM_ITEMS=(
  "System/Library/Extensions/AppleIntelFramebufferCapri.kext"
  "System/Library/Extensions/AppleIntelHD4000Graphics.kext"
  "System/Library/Extensions/AMDSupport.kext"
  "System/Library/Extensions/AMD10000Controller.kext"
  "System/Library/Extensions/AMD9500Controller.kext"
  "System/Library/Extensions/AMDFramebuffer.kext"
  "System/Library/Extensions/AMDRadeonVADriver2.bundle"
  "System/Library/Extensions/AMDRadeonX4000GLDriver.bundle"
  "System/Library/Extensions/AMDShared.bundle"
  "System/Library/Extensions/AMDMTLBronzeDriver.bundle"
  "System/Library/Extensions/AMDRadeonX4000.kext"
  "System/Library/Extensions/AMDRadeonX4000HWServices.kext"
)

typeset -a LIBRARY_ITEMS
LIBRARY_ITEMS=(
  "Library/Extensions/AppleIntelFramebufferCapri.kext"
  "Library/Extensions/AppleIntelHD4000Graphics.kext"
  "Library/Extensions/AMDRadeonX4000.kext"
  "Library/Extensions/AMDRadeonX4000HWServices.kext"
)

typeset -a HELPER_ITEMS
HELPER_ITEMS=(
  "Sequoia-12.5-Coherence-Validation/apply_sequoia_polaris_scanout_align_overlay.sh"
  "Sequoia-12.5-Coherence-Validation/enable_sequoia_polaris_accel_kc.sh"
  "Sequoia-12.5-Coherence-Validation/prepare_sequoia_polaris_amdcompat_no_igfxagdc_validation.sh"
  "Sequoia-12.5-Coherence-Validation/prepare_sequoia_polaris_full_12_5_coherence_validation.sh"
  "Sequoia-12.5-Coherence-Validation/repair_sequoia_ivybridge_aux_ownership.sh"
  "Sequoia-12.5-Coherence-Validation/set_efi_boot_args_amdcompat_no_igfxagdc.sh"
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

require_file() {
  local path="$1"
  [ -f "$path" ] || fail "missing file: $path"
}

copy_item() {
  local root="$1"
  local rel="$2"
  local src="${root}/${rel}"
  local dst="${SYSTEM_ARCHIVE}/${rel}"

  [ -e "$src" ] || fail "missing item: $src"
  mkdir -p "$(dirname "$dst")"
  ditto "$src" "$dst"
}

copy_helper_item() {
  local desktop_root="$1"
  local rel="$2"
  local src="${desktop_root%/}/${rel}"
  local dst="${HELPER_ARCHIVE}/${rel}"

  [ -e "$src" ] || return 0
  mkdir -p "$(dirname "$dst")"
  ditto "$src" "$dst"
}

bundle_manifest_line() {
  local bundle="$1"
  local info_plist="${bundle}/Contents/Info.plist"
  local owner group cfid short_ver bundle_ver osbundle

  owner="$(stat -f '%Su' "$bundle" 2>/dev/null || echo '?')"
  group="$(stat -f '%Sg' "$bundle" 2>/dev/null || echo '?')"
  cfid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || echo '?')"
  short_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || echo '?')"
  bundle_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || echo '?')"
  osbundle="$(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "$info_plist" 2>/dev/null || echo '(unset)')"

  printf '%s | owner=%s:%s | id=%s | short=%s | version=%s | OSBundleRequired=%s\n' \
    "$bundle" "$owner" "$group" "$cfid" "$short_ver" "$bundle_ver" "$osbundle"
}

capture_manifest() {
  local out="$1"
  shift

  : > "$out"
  for bundle in "$@"; do
    if [ -d "$bundle" ]; then
      bundle_manifest_line "$bundle" >> "$out"
      codesign -dv --verbose=4 "$bundle" >> "$out" 2>&1 || true
      printf '\n' >> "$out"
    fi
  done
}

require_dir "$TARGET"
require_dir "$EFI_ROOT"
require_file "${EFI_ROOT}/EFI/OC/config.plist"
require_file "$PROBE_SCRIPT"

mkdir -p "$BASELINE_DIR" "$PROBE_ROOT" "$EFI_ARCHIVE" "$SYSTEM_ARCHIVE" "$HELPER_ARCHIVE" "$MANIFEST_DIR"

info "Creating live working-state probe..."
PROBE_PATH="$(zsh "$PROBE_SCRIPT" "$PROBE_ROOT")"

info "Archiving EFI..."
ditto "${EFI_ROOT}/EFI" "${EFI_ARCHIVE}/EFI"

info "Archiving key system bundles..."
for rel in "${SYSTEM_ITEMS[@]}"; do
  copy_item "$TARGET" "$rel"
done

for rel in "${LIBRARY_ITEMS[@]}"; do
  copy_item "$TARGET" "$rel"
done

if [ -d "${TARGET}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions" ]; then
  mkdir -p "${SYSTEM_ARCHIVE}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC"
  ditto \
    "${TARGET}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions" \
    "${SYSTEM_ARCHIVE}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions"
fi

info "Archiving helper scripts..."
for rel in "${HELPER_ITEMS[@]}"; do
  copy_helper_item "${HOME}/Desktop" "$rel"
  copy_helper_item "${TARGET}/Users/$(id -un)/Desktop" "$rel"
done

info "Writing manifests..."
{
  echo "timestamp=${TS}"
  echo "os_version=${OS_VER}"
  echo "build_version=${BUILD_VER}"
  echo "target=${TARGET}"
  echo "efi_root=${EFI_ROOT}"
  echo "probe_path=${PROBE_PATH}"
} > "${MANIFEST_DIR}/baseline.txt"

nvram -p > "${MANIFEST_DIR}/nvram.txt" 2>&1 || true
kmutil showloaded > "${MANIFEST_DIR}/kmutil-showloaded.txt" 2>&1 || true
kmutil showloaded --collection aux --show all > "${MANIFEST_DIR}/kmutil-showloaded-aux.txt" 2>&1 || true
system_profiler SPDisplaysDataType > "${MANIFEST_DIR}/spdisplays.txt" 2>&1 || true
system_profiler SPPCIDataType > "${MANIFEST_DIR}/sppci.txt" 2>&1 || true

capture_manifest "${MANIFEST_DIR}/system-bundles.txt" \
  "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" \
  "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" \
  "${TARGET}/System/Library/Extensions/AMDSupport.kext" \
  "${TARGET}/System/Library/Extensions/AMD10000Controller.kext" \
  "${TARGET}/System/Library/Extensions/AMD9500Controller.kext" \
  "${TARGET}/System/Library/Extensions/AMDFramebuffer.kext" \
  "${TARGET}/System/Library/Extensions/AMDRadeonVADriver2.bundle" \
  "${TARGET}/System/Library/Extensions/AMDRadeonX4000GLDriver.bundle" \
  "${TARGET}/System/Library/Extensions/AMDShared.bundle" \
  "${TARGET}/System/Library/Extensions/AMDMTLBronzeDriver.bundle" \
  "${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext" \
  "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext"

capture_manifest "${MANIFEST_DIR}/library-bundles.txt" \
  "${TARGET}/Library/Extensions/AppleIntelFramebufferCapri.kext" \
  "${TARGET}/Library/Extensions/AppleIntelHD4000Graphics.kext" \
  "${TARGET}/Library/Extensions/AMDRadeonX4000.kext" \
  "${TARGET}/Library/Extensions/AMDRadeonX4000HWServices.kext"

if [ -d "${TARGET}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions" ]; then
  find "${TARGET}/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions" \
    -maxdepth 2 \
    \( -name 'AppleIntelFramebufferCapri.kext' -o -name 'AppleIntelHD4000Graphics.kext' -o -name 'AMDRadeonX4000.kext' -o -name 'AMDRadeonX4000HWServices.kext' -o -name 'AMDRadeonX4000HWLibs.kext' \) \
    -exec stat -f '%Su:%Sg %N' {} + \
    > "${MANIFEST_DIR}/aux-stash-ownership.txt" 2>&1 || true
fi

if [ -f "${EFI_ROOT}/EFI/OC/Kexts/Kryptonite.kext/Contents/MacOS/Kryptonite" ]; then
  /usr/bin/dwarfdump --uuid "${EFI_ROOT}/EFI/OC/Kexts/Kryptonite.kext/Contents/MacOS/Kryptonite" \
    > "${MANIFEST_DIR}/efi-kryptonite-uuid.txt" 2>&1 || true
fi

cat > "${BASELINE_DIR}/README.txt" <<EOF
Kryptonite working baseline archive

Timestamp: ${TS}
OS: ${OS_VER} (${BUILD_VER})

Contents:
- probe/: live probe bundle captured from the working Sequoia session
- efi/: mounted EFI used for that working boot
- system-root/: copied Intel + AMD bundles and Aux stash state
- helper-scripts/: helper scripts used to produce and repair this baseline
- manifests/: boot-args, loaded kexts, display state, signatures, ownership

Suggested reference checks:
- manifests/efi-kryptonite-uuid.txt
- manifests/system-bundles.txt
- manifests/library-bundles.txt
- manifests/aux-stash-ownership.txt
- probe/
EOF

info "Archived working baseline to:"
info "  ${BASELINE_DIR}"
