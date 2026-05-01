#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: prepare_sequoia_polaris_modern_amdshared_no_igfxagdc_validation.sh <mounted-system-volume> <efi-config-plist> [bronze-compat-root] [amdshared-compat-root] [modern-polaris-payload-root]

Prepare a single validation boot for the "compat Bronze, modern AMDShared"
hybrid stack on the now-stable no-kryigfxagdc boot profile:
  1. restore the compat Polaris scanout baseline
  2. refresh the Polaris AuxKC accelerator staging
  3. replace only AMDShared + VA/GL with the modern 13.5.2 set while keeping
     compat AMDMTLBronzeDriver
  4. set exact amdcompat boot-args without kryigfxagdc=1

Defaults:
  bronze-compat-root          /tmp/oclp-universal/12.5-23
  amdshared-compat-root       /tmp/oclp-universal/12.5
  modern-polaris-payload-root /tmp/oclp-universal/13.5.2

Run this from a stable helper OS such as Big Sur against an offline Sequoia
system volume and the EFI config.plist used to boot that Sequoia install.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 5 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
CFG="$2"
BRONZE_COMPAT_ROOT="${3:-/tmp/oclp-universal/12.5-23}"
AMDSHARED_COMPAT_ROOT="${4:-/tmp/oclp-universal/12.5}"
MODERN_PAYLOAD_ROOT="${5:-/tmp/oclp-universal/13.5.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_SCRIPT="${SCRIPT_DIR}/prepare_sequoia_polaris_modern_amdshared_validation.sh"
BOOTARGS_SCRIPT="${SCRIPT_DIR}/set_efi_boot_args_amdcompat_no_igfxagdc.sh"
ROLLBACK_SCRIPT="${SCRIPT_DIR}/set_efi_boot_args_amdcompat.sh"

[ -d "$TARGET" ] || { echo "missing target root: $TARGET" >&2; exit 1; }
[ -f "$CFG" ] || { echo "missing config.plist: $CFG" >&2; exit 1; }
[ -f "$PREP_SCRIPT" ] || { echo "missing modern AMDShared prep script: $PREP_SCRIPT" >&2; exit 1; }
[ -f "$BOOTARGS_SCRIPT" ] || { echo "missing boot-args script: $BOOTARGS_SCRIPT" >&2; exit 1; }
[ -f "$ROLLBACK_SCRIPT" ] || { echo "missing rollback boot-args script: $ROLLBACK_SCRIPT" >&2; exit 1; }

echo "Preparing Sequoia modern AMDShared validation without kryigfxagdc..."
echo "  target:            $TARGET"
echo "  config:            $CFG"
echo "  bronze compat:     $BRONZE_COMPAT_ROOT"
echo "  AMDShared compat:  $AMDSHARED_COMPAT_ROOT"
echo "  modern payload:    $MODERN_PAYLOAD_ROOT"
echo

zsh "$PREP_SCRIPT" "$TARGET" "$BRONZE_COMPAT_ROOT" "$AMDSHARED_COMPAT_ROOT" "$MODERN_PAYLOAD_ROOT"

echo
echo "Applying exact amdcompat boot-args without kryigfxagdc..."
zsh "$BOOTARGS_SCRIPT" "$CFG"

echo
echo "Validation root prepared."
echo "Next step: boot Sequoia with the eGPU and external display already attached."
echo "Avoid hotplugging on this pass so we don't mix in the separate AMDSupport connector panic."
echo "Rollback to the previous exact amdcompat args if needed:"
echo "  zsh ${ROLLBACK_SCRIPT} \"$CFG\""
