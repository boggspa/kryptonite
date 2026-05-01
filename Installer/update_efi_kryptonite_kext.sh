#!/bin/bash

# update_efi_kryptonite_kext.sh
# Replace only Kryptonite.kext on a mounted OpenCore EFI, preserving
# the existing config.plist and boot-args exactly as they are.

set -euo pipefail

DWARFDUMP_BIN="/usr/bin/dwarfdump"

kext_binary_uuid() {
  local kext_path="${1%/}"
  local binary_path="${kext_path}/Contents/MacOS/Kryptonite"
  local uuid_output

  [ -f "${binary_path}" ] || return 1
  [ -x "${DWARFDUMP_BIN}" ] || {
    echo "missing dwarfdump binary at ${DWARFDUMP_BIN}" >&2
    return 1
  }

  if ! uuid_output="$("${DWARFDUMP_BIN}" --uuid "${binary_path}" 2>&1)"; then
    echo "${uuid_output}" >&2
    return 1
  fi

  awk 'NR==1 {print $2}' <<<"${uuid_output}"
}

usage() {
  cat <<EOF
usage: update_efi_kryptonite_kext.sh <mounted-efi-root> [built-kext]

Defaults:
  built-kext  /tmp/kryptonite-build/Build/Products/Debug/Kryptonite.kext

This only updates EFI/OC/Kexts/Kryptonite.kext and does not touch:
  - config.plist
  - boot-args
  - Lilu.kext
EOF
}

target_root="${1:-}"
build_kext="${2:-/tmp/kryptonite-build/Build/Products/Debug/Kryptonite.kext}"

if [ -z "${target_root}" ] || [ "${target_root}" = "-h" ] || [ "${target_root}" = "--help" ]; then
  usage
  exit 0
fi

target_root="${target_root%/}"
target_oc="${target_root}/EFI/OC"
target_config="${target_oc}/config.plist"
target_kext="${target_oc}/Kexts/Kryptonite.kext"
timestamp="$(date +%Y%m%d-%H%M%S)"

[[ "${target_root}" == *"KRYPTONITE"* ]] && {
  echo "refusing to patch fallback KRYPTONITE EFI: ${target_root}" >&2
  exit 1
}

[ -d "${target_oc}" ] || { echo "OpenCore EFI not found at ${target_oc}" >&2; exit 1; }
[ -f "${target_config}" ] || { echo "OpenCore config not found at ${target_config}" >&2; exit 1; }
[ -d "${build_kext}" ] || { echo "Kryptonite build bundle not found at ${build_kext}" >&2; exit 1; }

mkdir -p "${target_oc}/Kexts"

if [ -d "${target_kext}" ]; then
  backup_kext="${target_kext}.backup-${timestamp}"
  echo "Backing up existing Kryptonite.kext to:"
  echo "  ${backup_kext}"
  ditto "${target_kext}" "${backup_kext}"
fi

echo "Installing Kryptonite.kext from:"
echo "  ${build_kext}"
echo "to:"
echo "  ${target_kext}"
ditto "${build_kext}" "${target_kext}"

build_uuid="$(kext_binary_uuid "${build_kext}")" || {
  echo "Unable to read UUID from build: ${build_kext}" >&2
  exit 1
}

installed_uuid="$(kext_binary_uuid "${target_kext}")" || {
  echo "Unable to read UUID from installed EFI kext: ${target_kext}" >&2
  exit 1
}

echo
echo "Build UUID:"
echo "  ${build_uuid}"
echo "EFI-installed UUID:"
echo "  ${installed_uuid}"

if [ "${build_uuid}" != "${installed_uuid}" ]; then
  echo "EFI Kryptonite UUID mismatch after install." >&2
  exit 1
fi

echo
echo "Kryptonite.kext updated successfully."
echo "config.plist and boot-args were left unchanged."
