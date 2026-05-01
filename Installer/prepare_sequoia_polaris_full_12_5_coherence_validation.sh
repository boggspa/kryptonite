#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: prepare_sequoia_polaris_full_12_5_coherence_validation.sh <mounted-system-volume> <efi-config-plist> [bronze-compat-root] [full-12.5-payload-root]

Prepare a single validation boot for a fully coherent 12.5 / 4.0.8 Polaris
stack on the stable no-kryigfxagdc boot profile:
  1. restore compat Bronze from 12.5-23
  2. restore AMDShared + scanout-side Polaris items from 12.5
  3. restore AuxKC Polaris accelerator staging from 12.5
  4. set exact amdcompat boot-args without kryigfxagdc=1

Defaults:
  bronze-compat-root    /tmp/oclp-universal/12.5-23
  full-12.5-payload-root /tmp/oclp-universal/12.5

Run this from a stable helper OS such as Big Sur against an offline Sequoia
system volume and the EFI config.plist used to boot that Sequoia install.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
CFG="$2"
BRONZE_COMPAT_ROOT="${3:-/tmp/oclp-universal/12.5-23}"
FULL_PAYLOAD_ROOT="${4:-/tmp/oclp-universal/12.5}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANOUT_SCRIPT="${SCRIPT_DIR}/apply_sequoia_polaris_scanout_align_overlay.sh"
AUX_SCRIPT="${SCRIPT_DIR}/enable_sequoia_polaris_accel_kc.sh"
BOOTARGS_SCRIPT="${SCRIPT_DIR}/set_efi_boot_args_amdcompat_no_igfxagdc.sh"
ROLLBACK_SCRIPT="${SCRIPT_DIR}/prepare_sequoia_polaris_amdcompat_no_igfxagdc_validation.sh"

[ -d "$TARGET" ] || { echo "missing target root: $TARGET" >&2; exit 1; }
[ -f "$CFG" ] || { echo "missing config.plist: $CFG" >&2; exit 1; }
[ -d "$BRONZE_COMPAT_ROOT" ] || { echo "missing bronze compat root: $BRONZE_COMPAT_ROOT" >&2; exit 1; }
[ -d "$FULL_PAYLOAD_ROOT" ] || { echo "missing 12.5 payload root: $FULL_PAYLOAD_ROOT" >&2; exit 1; }
[ -f "$SCANOUT_SCRIPT" ] || { echo "missing scanout baseline script: $SCANOUT_SCRIPT" >&2; exit 1; }
[ -f "$AUX_SCRIPT" ] || { echo "missing aux prep script: $AUX_SCRIPT" >&2; exit 1; }
[ -f "$BOOTARGS_SCRIPT" ] || { echo "missing boot-args script: $BOOTARGS_SCRIPT" >&2; exit 1; }
[ -f "$ROLLBACK_SCRIPT" ] || { echo "missing rollback prep script: $ROLLBACK_SCRIPT" >&2; exit 1; }

echo "Preparing Sequoia full 12.5 Polaris coherence validation..."
echo "  target:            $TARGET"
echo "  config:            $CFG"
echo "  bronze compat:     $BRONZE_COMPAT_ROOT"
echo "  full 12.5 payload: $FULL_PAYLOAD_ROOT"
echo

zsh "$SCANOUT_SCRIPT" "$TARGET" "$BRONZE_COMPAT_ROOT" "$FULL_PAYLOAD_ROOT" "$FULL_PAYLOAD_ROOT"
zsh "$AUX_SCRIPT" "$TARGET" "$FULL_PAYLOAD_ROOT"

echo
echo "Applying exact amdcompat boot-args without kryigfxagdc..."
zsh "$BOOTARGS_SCRIPT" "$CFG"

echo
echo "Validation root prepared."
echo "Next step: boot Sequoia with the eGPU and external display already attached."
echo "Avoid hotplugging on this pass so we don't mix in the separate AMDSupport connector panic."
echo "Rollback to the mixed 4.0.8/4.1.4 no-kryigfxagdc baseline if needed:"
echo "  zsh ${ROLLBACK_SCRIPT} \"$TARGET\" \"$CFG\" \"$BRONZE_COMPAT_ROOT\" \"$FULL_PAYLOAD_ROOT\" /tmp/oclp-universal/13.5.2"
