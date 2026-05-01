#!/bin/zsh

set -euo pipefail

DWARFDUMP_BIN="/usr/bin/dwarfdump"

usage() {
  cat <<'EOF'
usage: prepare_sequoia_polaris_amdcompat_no_igfxagdc_kryamdsurfguard_kryrad24_validation.sh <mounted-system-volume> <mounted-efi-root> [built-kext] [bronze-compat-root] [amdshared-compat-root] [modern-polaris-payload-root]

Prepare a single validation boot that:
  1. restores the stable compat Polaris Sequoia branch without kryigfxagdc
  2. updates EFI/OC/Kexts/Kryptonite.kext from a local build
  3. enables the experimental AMD IOSurface plane guard patch
  4. adds the AMD 24-bit output clamp to reduce scanout/compositor cost

Defaults:
  built-kext                  ~/Documents/kryptonite/BuildArtifacts/Kryptonite.kext
  bronze-compat-root          /tmp/oclp-universal/12.5-23
  amdshared-compat-root       /tmp/oclp-universal/12.5
  modern-polaris-payload-root /tmp/oclp-universal/13.5.2

Run this from a stable helper OS such as Big Sur against an offline Sequoia
system volume and the mounted EFI used to boot that Sequoia install.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 6 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
EFI_ROOT="${2%/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_KEXT="${3:-${HOME}/Documents/kryptonite/BuildArtifacts/Kryptonite.kext}"
BRONZE_COMPAT_ROOT="${4:-/tmp/oclp-universal/12.5-23}"
AMDSHARED_COMPAT_ROOT="${5:-/tmp/oclp-universal/12.5}"
MODERN_PAYLOAD_ROOT="${6:-/tmp/oclp-universal/13.5.2}"
CFG="${EFI_ROOT}/EFI/OC/config.plist"
BASELINE_SCRIPT="${SCRIPT_DIR}/prepare_sequoia_polaris_amdcompat_no_igfxagdc_validation.sh"
UPDATE_KEXT_SCRIPT="${SCRIPT_DIR}/update_efi_kryptonite_kext.sh"
BOOTARGS_SCRIPT="${SCRIPT_DIR}/set_efi_boot_args_amdcompat_no_igfxagdc_kryamdsurfguard_kryrad24.sh"
ROLLBACK_SCRIPT="${SCRIPT_DIR}/set_efi_boot_args_amdcompat_no_igfxagdc_kryamdsurfguard.sh"

[ -d "$TARGET" ] || { echo "missing target root: $TARGET" >&2; exit 1; }
[ -d "$EFI_ROOT" ] || { echo "missing EFI root: $EFI_ROOT" >&2; exit 1; }
[ -f "$CFG" ] || { echo "missing config.plist: $CFG" >&2; exit 1; }
[ -d "$BUILD_KEXT" ] || { echo "missing built kext: $BUILD_KEXT" >&2; exit 1; }
[ -f "$BASELINE_SCRIPT" ] || { echo "missing baseline prep script: $BASELINE_SCRIPT" >&2; exit 1; }
[ -f "$UPDATE_KEXT_SCRIPT" ] || { echo "missing EFI update script: $UPDATE_KEXT_SCRIPT" >&2; exit 1; }
[ -f "$BOOTARGS_SCRIPT" ] || { echo "missing boot-args script: $BOOTARGS_SCRIPT" >&2; exit 1; }
[ -f "$ROLLBACK_SCRIPT" ] || { echo "missing rollback boot-args script: $ROLLBACK_SCRIPT" >&2; exit 1; }

echo "Preparing Sequoia amdcompat validation with AMD IOSurface guard and 24-bit output clamp..."
echo "  target:            $TARGET"
echo "  EFI root:          $EFI_ROOT"
echo "  config:            $CFG"
echo "  build kext:        $BUILD_KEXT"
echo "  bronze compat:     $BRONZE_COMPAT_ROOT"
echo "  AMDShared compat:  $AMDSHARED_COMPAT_ROOT"
echo "  modern payload:    $MODERN_PAYLOAD_ROOT"
echo

zsh "$BASELINE_SCRIPT" "$TARGET" "$CFG" "$BRONZE_COMPAT_ROOT" "$AMDSHARED_COMPAT_ROOT" "$MODERN_PAYLOAD_ROOT"

echo
echo "Updating mounted EFI with the experimental Kryptonite build..."
zsh "$UPDATE_KEXT_SCRIPT" "$EFI_ROOT" "$BUILD_KEXT"

echo
echo "Applying exact amdcompat boot-args without kryigfxagdc and with kryamdsurfguard + kryrad24..."
zsh "$BOOTARGS_SCRIPT" "$CFG"

EXPECTED_UUID="$(${DWARFDUMP_BIN} --uuid "${BUILD_KEXT}/Contents/MacOS/Kryptonite" 2>/dev/null | awk 'NR==1 {print $2}')"

echo
echo "Validation root prepared."
if [ -n "${EXPECTED_UUID:-}" ]; then
  echo "Expected Kryptonite UUID on next Sequoia boot:"
  echo "  ${EXPECTED_UUID}"
fi
echo "Next step: boot Sequoia with the eGPU and external display already attached."
echo "Avoid hotplugging on this pass so we don't mix in the separate AMDSupport connector panic."
echo "Rollback to the no-kryigfxagdc kryamdsurfguard args if needed:"
echo "  zsh ${ROLLBACK_SCRIPT} \"$CFG\""
