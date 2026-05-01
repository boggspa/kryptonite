#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: enable_sequoia_polaris_accel_kc.sh <target-root> [oclp-payload-root]

Restore the modern OCLP Polaris accelerator pair and prepare it for the
Sequoia Auxiliary Kernel Collection:
  - restore fresh AMDRadeonX4000.kext from the OCLP payload
  - restore fresh AMDRadeonX4000HWServices.kext from the OCLP payload
  - preserve the runtime IOPropertyMatch gates
  - set OSBundleRequired=Auxiliary on the accelerator kexts
  - set OSBundleRequired=Auxiliary on nested HWLibs plug-ins
  - re-sign the modified bundles

Run this from a stable boot OS such as Big Sur against an offline Sequoia
system volume.

Defaults:
  oclp-payload-root  /tmp/oclp-universal/13.5.2
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
PAYLOAD_ROOT="${2:-/tmp/oclp-universal/13.5.2}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-polaris-accel-kc"
LIB_EXT_ROOT="${TARGET}/Library/Extensions"

typeset -a TARGET_ITEMS
TARGET_ITEMS=(
  "System/Library/Extensions/AMDRadeonX4000.kext"
  "System/Library/Extensions/AMDRadeonX4000HWServices.kext"
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

typeset -a AUX_STAGE_ITEMS
AUX_STAGE_ITEMS=(
  "AMDRadeonX4000.kext"
  "AMDRadeonX4000HWServices.kext"
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

remove_if_present() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    /bin/rm -rf "$path"
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

resign_bundle_adhoc() {
  local bundle="$1"
  local allocate=""
  allocate="$(find_codesign_allocate)" || fail "could not locate codesign_allocate; install Xcode or export CODESIGN_ALLOCATE"
  CODESIGN_ALLOCATE="$allocate" codesign --force --sign - --timestamp=none "$bundle"
}

bundle_signature_details() {
  local bundle="$1"
  codesign -dv --verbose=4 "$bundle" 2>&1
}

bundle_signature_is_adhoc() {
  local bundle="$1"
  bundle_signature_details "$bundle" | /usr/bin/grep -q "Signature=adhoc"
}

bundle_info_plist_not_bound() {
  local bundle="$1"
  bundle_signature_details "$bundle" | /usr/bin/grep -q "Info.plist=not bound"
}

preserve_or_resign_bundle() {
  local bundle="$1"

  if ! bundle_signature_is_adhoc "$bundle" && bundle_info_plist_not_bound "$bundle"; then
    info "  preserved existing signature on $(basename "$bundle")"
    return 0
  fi

  resign_bundle_adhoc "$bundle"
  info "  re-signed $(basename "$bundle")"
}

report_bundle_signature_state() {
  local bundle="$1"

  if bundle_signature_is_adhoc "$bundle"; then
    info "  signature adhoc on $(basename "$bundle")"
  elif bundle_info_plist_not_bound "$bundle"; then
    info "  preserved existing signature on $(basename "$bundle")"
  else
    info "  signature present on $(basename "$bundle")"
  fi
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

kmutil_supports_flag() {
  local flag="$1"
  kmutil install --help 2>/dev/null | grep -q -- "$flag"
}

backup_item() {
  local rel="$1"
  local src="${TARGET}/${rel}"
  local dst="${BACKUP_ROOT}/${rel}"
  [ -e "$src" ] || fail "missing target item: $src"
  mkdir -p "$(dirname "$dst")"
  ditto "$src" "$dst"
}

restore_item_from_payload() {
  local rel="$1"
  local src="${PAYLOAD_ROOT}/${rel}"
  local dst="${TARGET}/${rel}"
  require_item "$PAYLOAD_ROOT" "$rel"
  remove_if_present "$dst"
  ditto "$src" "$dst"
}

stage_item_to_library_extensions() {
  local system_rel="$1"
  local name="$2"
  local src="${TARGET}/${system_rel}"
  local dst="${LIB_EXT_ROOT}/${name}"
  remove_if_present "$dst"
  ditto "$src" "$dst"
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

delete_plist_key_if_present() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Delete ${key}" "$plist" >/dev/null 2>&1 || true
}

print_kc_presence() {
  local kc="${TARGET}/System/Library/KernelCollections/SystemKernelExtensions.kc"
  info "System KC currently contains:"
  for bundle_id in \
    "com.apple.kext.AMDSupport" \
    "com.apple.kext.AMD9500Controller" \
    "com.apple.kext.AMDFramebuffer" \
    "com.apple.kext.AMDRadeonX4000" \
    "com.apple.kext.AMDRadeonX4000HWServices"
  do
    if /usr/bin/grep -a -q "$bundle_id" "$kc"; then
      info "  present ${bundle_id}"
    else
      info "  missing ${bundle_id}"
    fi
  done
}

print_osbundle_state() {
  local x4000_plist="${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext/Contents/Info.plist"
  local hws_plist="${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/Info.plist"
  local plugin_plist=""

  info "Current Auxiliary prep state:"
  info "  AMDRadeonX4000.kext OSBundleRequired: $(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "$x4000_plist" 2>/dev/null || echo '(unset)')"
  info "  AMDRadeonX4000HWServices.kext OSBundleRequired: $(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "$hws_plist" 2>/dev/null || echo '(unset)')"

  for plugin_plist in "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/PlugIns/"*.kext/Contents/Info.plist; do
    [ -f "$plugin_plist" ] || continue
    info "  $(basename "$(dirname "$(dirname "$plugin_plist")")") OSBundleRequired: $(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "$plugin_plist" 2>/dev/null || echo '(unset)')"
  done
}

print_library_extensions_state() {
  local staged=""
  info "Current /Library/Extensions Polaris staging:"
  for staged in "${AUX_STAGE_ITEMS[@]}"; do
    if [ -d "${LIB_EXT_ROOT}/${staged}" ]; then
      info "  present ${LIB_EXT_ROOT}/${staged}"
      info "    owner $(stat -f '%u:%g' "${LIB_EXT_ROOT}/${staged}")"
      info "    OSBundleRequired $(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "${LIB_EXT_ROOT}/${staged}/Contents/Info.plist" 2>/dev/null || echo '(unset)')"
      if bundle_signature_is_adhoc "${LIB_EXT_ROOT}/${staged}"; then
        info "    signature adhoc"
      else
        info "    signature preserved"
      fi
    else
      info "  missing ${LIB_EXT_ROOT}/${staged}"
    fi
  done
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

[ -d "$TARGET" ] || fail "missing directory: $TARGET"
require_dir "$PAYLOAD_ROOT"

for rel in "${TARGET_ITEMS[@]}"; do
  [ -d "${TARGET}/${rel}" ] || fail "missing bundle: ${TARGET}/${rel}"
  require_item "$PAYLOAD_ROOT" "$rel"
done

mkdir -p "$BACKUP_ROOT"

info "Target root: ${TARGET}"
info "OCLP payload: ${PAYLOAD_ROOT}"
info "Backup root: ${BACKUP_ROOT}"
print_kc_presence

remount_target_rw

info
info "Backing up current Polaris accelerator bundles..."
for rel in "${TARGET_ITEMS[@]}"; do
  backup_item "$rel"
  info "  backed up ${rel}"
done

info
info "Restoring fresh Polaris accelerator bundles from the modern payload..."
for rel in "${TARGET_ITEMS[@]}"; do
  restore_item_from_payload "$rel"
  info "  restored ${rel}"
done

mkdir -p "$LIB_EXT_ROOT"

info
info "Preparing Polaris accelerator bundles for Auxiliary KC..."
X4000_PLIST="${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext/Contents/Info.plist"
HWS_PLIST="${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/Info.plist"
set_osbundle_required "$X4000_PLIST" "Auxiliary"
set_osbundle_required "$HWS_PLIST" "Auxiliary"
info "  set AMDRadeonX4000.kext OSBundleRequired=Auxiliary"
info "  set AMDRadeonX4000HWServices.kext OSBundleRequired=Auxiliary"

for plugin_plist in "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/PlugIns/"*.kext/Contents/Info.plist; do
  [ -f "$plugin_plist" ] || continue
  set_osbundle_required "$plugin_plist" "Auxiliary"
  info "  set $(basename "$(dirname "$(dirname "$plugin_plist")")") OSBundleRequired=Auxiliary"
done

info
info "Normalizing Polaris bundle ownership to root:wheel..."
for plugin_dir in "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/PlugIns/"*.kext; do
  [ -d "$plugin_dir" ] || continue
  normalize_bundle_ownership "$plugin_dir"
  info "  fixed ownership on $(basename "$plugin_dir")"
done
normalize_bundle_ownership "${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext"
normalize_bundle_ownership "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext"
info "  fixed ownership on AMDRadeonX4000.kext"
info "  fixed ownership on AMDRadeonX4000HWServices.kext"

info
info "Preserving original Polaris bundle signatures..."
for plugin_dir in "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext/Contents/PlugIns/"*.kext; do
  [ -d "$plugin_dir" ] || continue
  report_bundle_signature_state "$plugin_dir"
done
report_bundle_signature_state "${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext"
report_bundle_signature_state "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext"

info
info "Staging Polaris accelerator copies into /Library/Extensions..."
stage_item_to_library_extensions "System/Library/Extensions/AMDRadeonX4000.kext" "AMDRadeonX4000.kext"
stage_item_to_library_extensions "System/Library/Extensions/AMDRadeonX4000HWServices.kext" "AMDRadeonX4000HWServices.kext"
normalize_bundle_ownership "${LIB_EXT_ROOT}/AMDRadeonX4000.kext"
normalize_bundle_ownership "${LIB_EXT_ROOT}/AMDRadeonX4000HWServices.kext"
for plugin_dir in "${LIB_EXT_ROOT}/AMDRadeonX4000HWServices.kext/Contents/PlugIns/"*.kext; do
  [ -d "$plugin_dir" ] || continue
  normalize_bundle_ownership "$plugin_dir"
  report_bundle_signature_state "$plugin_dir"
done
report_bundle_signature_state "${LIB_EXT_ROOT}/AMDRadeonX4000.kext"
report_bundle_signature_state "${LIB_EXT_ROOT}/AMDRadeonX4000HWServices.kext"
info "  staged ${LIB_EXT_ROOT}/AMDRadeonX4000.kext"
info "  staged ${LIB_EXT_ROOT}/AMDRadeonX4000HWServices.kext"

rebuild_collections
normalize_stashed_aux_ownership
create_root_snapshot

info
print_kc_presence
print_osbundle_state
print_library_extensions_state
info "Note: AMDRadeonX4000* may remain absent from SystemKernelExtensions.kc after Auxiliary prep."
info "      The real validation is post-reboot: loaded kexts and a live external image."
info
info "Polaris accelerator Auxiliary KC preparation complete."
