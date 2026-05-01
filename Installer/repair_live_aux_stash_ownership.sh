#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: repair_live_aux_stash_ownership.sh

Normalize ownership for the current live AuxKC stashed graphics bundles on the
booted Sequoia system.

This touches matching bundles under:
  /private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions

Targets:
  - AppleIntelFramebufferCapri.kext
  - AppleIntelHD4000Graphics.kext
  - AMDRadeonX4000.kext
  - AMDRadeonX4000HWServices.kext
  - AMDRadeonX4000HWLibs.kext
  - AMDRadeonX4100HWLibs.kext
  - AMDRadeonX4200HWLibs.kext
  - AMDRadeonX4400HWLibs.kext
  - AMDRadeonX4700HWLibs.kext
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 0 ]; then
  usage
  exit 0
fi

STASH_ROOT="/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/StashedExtensions"

typeset -a TARGET_NAMES
TARGET_NAMES=(
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

info() {
  printf '%s\n' "$*"
}

normalize_bundle_ownership() {
  local bundle="$1"
  /usr/sbin/chown -R 0:0 "$bundle"
}

print_bundle_state() {
  local bundle="$1"
  info "  $(stat -f '%u:%g %N' "$bundle")"
}

if [ ! -d "$STASH_ROOT" ]; then
  printf 'missing stash root: %s\n' "$STASH_ROOT" >&2
  exit 1
fi

info "Live AuxKC stash root: ${STASH_ROOT}"
info
info "Normalizing live AuxKC stashed ownership..."

found_any=0
for name in "${TARGET_NAMES[@]}"; do
  for bundle in "${STASH_ROOT}"/*/"${name}"; do
    [ -d "$bundle" ] || continue
    normalize_bundle_ownership "$bundle"
    print_bundle_state "$bundle"
    found_any=1
  done
done

if [ "$found_any" -eq 0 ]; then
  info "  no matching stashed bundles found"
fi

info
info "Live AuxKC stash ownership repair complete."
