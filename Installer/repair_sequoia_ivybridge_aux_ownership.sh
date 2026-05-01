#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: repair_sequoia_ivybridge_aux_ownership.sh <mounted-system-volume>

Repair the system, staged, and stashed Ivy Bridge Auxiliary kext ownership on
an offline Sequoia volume, then rebuild the target kernel collections and
create a fresh root snapshot.

This only touches:
  - /System/Library/Extensions/AppleIntelFramebufferCapri.kext
  - /System/Library/Extensions/AppleIntelHD4000Graphics.kext
  - /Library/Extensions/AppleIntelFramebufferCapri.kext
  - /Library/Extensions/AppleIntelHD4000Graphics.kext
  - /private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions/.../AppleIntelFramebufferCapri.kext
  - /private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions/.../AppleIntelHD4000Graphics.kext

Use this when:
  - Radeon external display output is working
  - the internal LCD still falls back to generic 3 MB "Display"
  - probe output shows the LCD attached to .Display_boot instead of Capri
  - Intel Capri/HD4000 bundles drifted to user ownership such as 502:20
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 1 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-ivybridge-aux-ownership-repair"

typeset -a INTEL_SYSTEM_ITEMS
INTEL_SYSTEM_ITEMS=(
  "System/Library/Extensions/AppleIntelFramebufferCapri.kext"
  "System/Library/Extensions/AppleIntelHD4000Graphics.kext"
)

typeset -a INTEL_AUX_STAGE_ITEMS
INTEL_AUX_STAGE_ITEMS=(
  "Library/Extensions/AppleIntelFramebufferCapri.kext"
  "Library/Extensions/AppleIntelHD4000Graphics.kext"
)

typeset -a INTEL_AUX_STASH_ITEM_NAMES
INTEL_AUX_STASH_ITEM_NAMES=(
  "AppleIntelFramebufferCapri.kext"
  "AppleIntelHD4000Graphics.kext"
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
  [ -e "${root}/${rel}" ] || fail "missing item: ${root}/${rel}"
}

normalize_bundle_ownership() {
  local bundle="$1"
  /usr/sbin/chown -R 0:0 "$bundle"
}

kmutil_supports_flag() {
  local flag="$1"
  kmutil install --help 2>/dev/null | grep -q -- "$flag"
}

remount_target_rw() {
  info "Attempting to remount target read/write..."
  if mount -uw "$TARGET" 2>/dev/null; then
    info "  remounted ${TARGET} read/write"
  else
    fail "could not remount ${TARGET} read/write"
  fi
}

backup_bundle() {
  local rel="$1"
  local src="${TARGET}/${rel}"
  local dst="${BACKUP_ROOT}/${rel}"

  mkdir -p "$(dirname "$dst")"
  ditto "$src" "$dst"
}

print_bundle_state() {
  local rel="$1"
  local bundle="${TARGET}/${rel}"
  local plist="${bundle}/Contents/Info.plist"
  local ownership osbundle
  ownership="$(stat -f '%u:%g' "$bundle")"
  osbundle="$(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "$plist" 2>/dev/null || echo '(unset)')"
  info "  ${rel}"
  info "    owner ${ownership}"
  info "    OSBundleRequired ${osbundle}"
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
  info "Normalizing stashed Ivy Bridge Auxiliary ownership..."

  if [ ! -d "$stash_root" ]; then
    info "  skipped missing ${stash_root}"
    return
  fi

  for name in "${INTEL_AUX_STASH_ITEM_NAMES[@]}"; do
    for bundle in "${stash_root}"/*/"${name}"; do
      [ -d "$bundle" ] || continue
      normalize_bundle_ownership "$bundle"
      info "  normalized ${bundle}"
      found_any=1
    done
  done

  if [ "$found_any" -eq 0 ]; then
    info "  no matching stashed Ivy Bridge Auxiliary bundles found"
  fi
}

require_dir "$TARGET"

for rel in "${INTEL_AUX_STAGE_ITEMS[@]}"; do
  require_item "$TARGET" "$rel"
done

for rel in "${INTEL_SYSTEM_ITEMS[@]}"; do
  require_item "$TARGET" "$rel"
done

mkdir -p "$BACKUP_ROOT"

info "Target root: ${TARGET}"
info "Backup root: ${BACKUP_ROOT}"

remount_target_rw

info
info "Backing up current system Ivy Bridge Intel items..."
for rel in "${INTEL_SYSTEM_ITEMS[@]}"; do
  backup_bundle "$rel"
  info "  backed up ${rel}"
done

info
info "Backing up current staged Ivy Bridge Auxiliary items..."
for rel in "${INTEL_AUX_STAGE_ITEMS[@]}"; do
  backup_bundle "$rel"
  info "  backed up ${rel}"
done

info
info "Normalizing system Ivy Bridge Intel ownership..."
for rel in "${INTEL_SYSTEM_ITEMS[@]}"; do
  normalize_bundle_ownership "${TARGET}/${rel}"
  info "  normalized ${rel}"
done

info
info "Normalizing staged Ivy Bridge Auxiliary ownership..."
for rel in "${INTEL_AUX_STAGE_ITEMS[@]}"; do
  normalize_bundle_ownership "${TARGET}/${rel}"
  info "  normalized ${rel}"
done

info
info "Current system Ivy Bridge Intel state:"
for rel in "${INTEL_SYSTEM_ITEMS[@]}"; do
  print_bundle_state "$rel"
done

info
info "Current staged Ivy Bridge Auxiliary state:"
for rel in "${INTEL_AUX_STAGE_ITEMS[@]}"; do
  print_bundle_state "$rel"
done

rebuild_collections
normalize_stashed_aux_ownership
create_root_snapshot

info
info "Ivy Bridge Auxiliary ownership repair complete."
