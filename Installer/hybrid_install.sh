#!/bin/bash

# hybrid_install.sh
# Inject Kryptonite and Lilu into an existing OpenCore EFI without
# touching the fallback Kryptonite EFI volume.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

# Ensure tput in tools.sh has a usable terminal definition.
if [ -z "${TERM:-}" ] || [ "${TERM}" = "dumb" ]; then
  export TERM="xterm"
fi

cd "${script_dir}"

source "${script_dir}/tools.sh"
source "${script_dir}/plists.sh"
source "${script_dir}/opencore.sh"
source "${script_dir}/resources.sh"
source "${script_dir}/hardware.sh"

usage() {
  printfn "Usage:"
  printfn "  ${b}hybrid_install.sh${n} <mounted-efi-volume-root> [build-kext] [lilu-kext]"
  printfn ""
  printfn "Defaults:"
  printfn "  build-kext: ${b}/tmp/kryptonite-build/Build/Products/Debug/Kryptonite.kext${n}"
  printfn "  lilu-kext:  ${b}${repo_root}/Kryptonite/Lilu.kext${n}"
}

target_root="${1:-}"
build_kext="${2:-/tmp/kryptonite-build/Build/Products/Debug/Kryptonite.kext}"
lilu_kext="${3:-${repo_root}/Kryptonite/Lilu.kext}"

if [ -z "${target_root}" ] || [ "${target_root}" = "-h" ] || [ "${target_root}" = "--help" ]; then
  usage
  exit 0
fi

target_root="${target_root%/}"
target_oc="${target_root}/EFI/OC"
target_config="${target_oc}/config.plist"
target_kexts="${target_oc}/Kexts"

if [[ "${target_root}" == *"KRYPTONITE"* ]]; then
  exit_err "Refusing to patch the KRYPTONITE fallback EFI. Point this at the Sequoia-capable EFI volume instead."
fi

[ -d "${target_oc}" ] || exit_err "OpenCore EFI not found at ${target_oc}."
[ -f "${target_config}" ] || exit_err "OpenCore config not found at ${target_config}."
[ -d "${build_kext}" ] || exit_err "Kryptonite build bundle not found at ${build_kext}."
[ -d "${lilu_kext}" ] || exit_err "Lilu bundle not found at ${lilu_kext}."

kry_gpu="${KRY_GPU:-AMD}"
kry_tbt="${KRY_TBTV:-}"
if [ -z "${kry_tbt}" ]; then
  hardware_get_tbver || true
  if [ -n "${hardware_tbver:-}" ]; then
    kry_tbt="${hardware_tbver}"
  else
    # Mid-2012 MBP commonly reports TB2 in this project flow.
    kry_tbt="2"
  fi
fi

profile="${KRY_PROFILE:-default}"
case "${profile}" in
  default)
    bootargs=("-lilubeta" "-krybeta" "krygpu=${kry_gpu}" "krytbtv=${kry_tbt}")
    ;;
  probe)
    bootargs=("-lilubeta" "-krybeta" "krygpu=${kry_gpu}" "krytbtv=${kry_tbt}" "kryprobe=1")
    ;;
  agdc-off)
    bootargs=("-lilubeta" "-krybeta" "krygpu=${kry_gpu}" "krytbtv=${kry_tbt}" "kryskipagdc=1")
    ;;
  iopci-off)
    bootargs=("-lilubeta" "-krybeta" "krygpu=${kry_gpu}" "krytbtv=${kry_tbt}" "kryskipiopci=1")
    ;;
  safe)
    bootargs=(
      "-lilubeta"
      "-krybeta"
      "krygpu=${kry_gpu}"
      "krytbtv=${kry_tbt}"
      "kryskipagdc=1"
      "kryskipiopci=1"
    )
    ;;
  *)
    exit_err "Unknown KRY_PROFILE '${profile}'. Supported: default, probe, agdc-off, iopci-off, safe."
    ;;
esac

if [ -n "${KRY_EXTRA_BOOTARGS:-}" ]; then
  read -r -a extra_bootargs <<< "${KRY_EXTRA_BOOTARGS}"
  bootargs+=("${extra_bootargs[@]}")
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="${target_oc}.backup-${timestamp}"

printfn "${b}Backing up EFI pieces...${n}"
mkdir -p "${backup_dir}"
ditto "${target_config}" "${backup_dir}/config.plist"

if [ -d "${target_kexts}/Kryptonite.kext" ]; then
  ditto "${target_kexts}/Kryptonite.kext" "${backup_dir}/Kryptonite.kext"
fi

if [ -d "${target_kexts}/Lilu.kext" ]; then
  ditto "${target_kexts}/Lilu.kext" "${backup_dir}/Lilu.kext"
fi

tempdir="$(mktemp -d /tmp/kryptonite-hybrid.XXXXXX)"
trap 'cleanup "${tempdir}"' EXIT

printfn "${b}Staging hybrid EFI payload...${n}"
mkdir -p "${tempdir}/EFI/OC/Kexts"
ditto "${lilu_kext}" "${tempdir}/EFI/OC/Kexts/Lilu.kext"
ditto "${build_kext}" "${tempdir}/EFI/OC/Kexts/Kryptonite.kext"

resources_oc_efi_dir="${tempdir}/EFI"
resources_move_kextsonly "${target_root}"

printfn "${b}Updating OpenCore config...${n}"
opencore_add_kry_injections "${target_config}"
if [ "${KRY_DEBUG:-0}" = "1" ]; then
  bootargs+=("-liludbg" "-krydbg" "liludump=60")
fi
opencore_set_bootargs "${target_config}" "${bootargs[@]}"

printfn ""
printfn "${b}Hybrid EFI updated.${n}"
printfn "Target:  ${target_root}"
printfn "Backup:  ${backup_dir}"
printfn "Kexts:   Lilu.kext + Kryptonite.kext"
printfn "Profile: ${profile}"
printfn "Boot-args added: ${bootargs[*]}"
