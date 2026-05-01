#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_full_hybrid_graphics_stack.sh <target-root> <polaris-stash-dir> [oclp-payload-root]

Restore a complete custom Sequoia graphics stack in one pass:
  - exact Ivy Bridge + AppleGVA payload from OCLP Universal-Binaries
  - exact Polaris payload from a previously stashed Sequoia root patch

Defaults:
  oclp-payload-root  /tmp/oclp-universal/11.7.10

Recommended flow:
  1. Mount OCLP Universal-Binaries.dmg.
  2. Boot a stable OS such as Big Sur.
  3. Run this against the mounted Sequoia system volume.
  4. Reboot Sequoia with no eGPU first, then test eGPU.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
POLARIS_STASH="${2%/}"
PAYLOAD_ROOT="${3:-/tmp/oclp-universal/11.7.10}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-full-hybrid-graphics"

typeset -a INTEL_ITEMS
INTEL_ITEMS=(
  "System/Library/Extensions/AppleIntelFramebufferCapri.kext"
  "System/Library/Extensions/AppleIntelHD4000Graphics.kext"
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

typeset -a POLARIS_ITEMS
POLARIS_ITEMS=(
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

find_codesign_allocate() {
  local candidate=""

  if [ -n "${CODESIGN_ALLOCATE:-}" ] && [ -x "${CODESIGN_ALLOCATE}" ]; then
    printf '%s\n' "${CODESIGN_ALLOCATE}"
    return 0
  fi

  for candidate in \
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate" \
    "/Volumes/Sonoma/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate" \
    "/Volumes/BigSur/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
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

kmutil_supports_flag() {
  local flag="$1"
  kmutil install --help 2>/dev/null | grep -q -- "$flag"
}

resign_bundle_adhoc() {
  local bundle="$1"
  local allocate=""
  allocate="$(find_codesign_allocate)" || fail "could not locate codesign_allocate; install Xcode or export CODESIGN_ALLOCATE"
  CODESIGN_ALLOCATE="$allocate" codesign --force --sign - --timestamp=none "$bundle"
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
  resign_bundle_adhoc "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext"
  resign_bundle_adhoc "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext"
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

print_source_state() {
  info "Ivy Bridge source:"
  for rel in "${INTEL_ITEMS[@]}"; do
    info "  ${rel}$(bundle_version_summary "$PAYLOAD_ROOT" "$rel")"
  done
  info "Polaris stash:"
  for rel in "${POLARIS_ITEMS[@]}"; do
    info "  ${rel}"
  done
}

require_dir "$TARGET"
require_dir "$PAYLOAD_ROOT"
require_dir "$POLARIS_STASH"

for rel in "${INTEL_ITEMS[@]}"; do
  require_item "$PAYLOAD_ROOT" "$rel"
done

for rel in "${GVA_ITEMS[@]}"; do
  require_item "$PAYLOAD_ROOT" "$rel"
done

for rel in "${POLARIS_ITEMS[@]}"; do
  require_item "$POLARIS_STASH" "$rel"
done

framework_binary_missing "$PAYLOAD_ROOT" "AppleGVA" && fail "payload AppleGVA.framework is broken or missing"
framework_binary_missing "$PAYLOAD_ROOT" "AppleGVACore" && fail "payload AppleGVACore.framework is broken or missing"

mkdir -p "$BACKUP_ROOT"

info "Target root:      ${TARGET}"
info "OCLP payload:     ${PAYLOAD_ROOT}"
info "Polaris stash:    ${POLARIS_STASH}"
info "Backup root:      ${BACKUP_ROOT}"
print_source_state

remount_target_rw

info
info "Restoring exact OCLP Ivy Bridge stack..."
for rel in "${INTEL_ITEMS[@]}"; do
  backup_and_replace "$PAYLOAD_ROOT" "$rel"
  info "  restored ${rel}"
done

info
info "Restoring exact OCLP AppleGVA stack..."
for rel in "${GVA_ITEMS[@]}"; do
  backup_and_replace "$PAYLOAD_ROOT" "$rel"
  info "  restored ${rel}"
done

info
info "Enabling Ivy Bridge AuxKC support..."
enable_intel_auxkc_support
info "  set AppleIntelFramebufferCapri.kext OSBundleRequired=Auxiliary"
info "  set AppleIntelHD4000Graphics.kext OSBundleRequired=Auxiliary"
info "  ad-hoc re-signed both Intel kexts after plist edits"

info
info "Restoring stashed Polaris stack..."
for rel in "${POLARIS_ITEMS[@]}"; do
  backup_and_replace "$POLARIS_STASH" "$rel"
  info "  restored ${rel}"
done

rebuild_collections
create_root_snapshot

info
info "Full hybrid graphics overlay complete."
