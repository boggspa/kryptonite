#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: prepare_sequoia_polaris_modern_amdshared_validation.sh <mounted-system-volume> [bronze-compat-root] [amdshared-compat-root] [modern-polaris-payload-root]

Prepare a single validation boot for the "compat Bronze, modern AMDShared"
hybrid stack:
  1. restore the known-good compat Polaris scanout baseline
  2. refresh the Polaris AuxKC accelerator staging
  3. replace only AMDShared + VA/GL with the modern 13.5.2 set while keeping
     compat AMDMTLBronzeDriver

Defaults:
  bronze-compat-root          /tmp/oclp-universal/12.5-23
  amdshared-compat-root       /tmp/oclp-universal/12.5
  modern-polaris-payload-root /tmp/oclp-universal/13.5.2

Run this from a stable helper OS such as Big Sur against an offline Sequoia
system volume.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 4 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
BRONZE_COMPAT_ROOT="${2:-/tmp/oclp-universal/12.5-23}"
AMDSHARED_COMPAT_ROOT="${3:-/tmp/oclp-universal/12.5}"
MODERN_PAYLOAD_ROOT="${4:-/tmp/oclp-universal/13.5.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANOUT_SCRIPT="${SCRIPT_DIR}/apply_sequoia_polaris_scanout_align_overlay.sh"
AUX_SCRIPT="${SCRIPT_DIR}/enable_sequoia_polaris_accel_kc.sh"
BRONZE_COMPAT_SCRIPT="${SCRIPT_DIR}/apply_sequoia_bronze_compat_overlay.sh"

[ -d "$TARGET" ] || { echo "missing target root: $TARGET" >&2; exit 1; }
[ -f "$SCANOUT_SCRIPT" ] || { echo "missing scanout baseline script: $SCANOUT_SCRIPT" >&2; exit 1; }
[ -f "$AUX_SCRIPT" ] || { echo "missing aux prep script: $AUX_SCRIPT" >&2; exit 1; }
[ -f "$BRONZE_COMPAT_SCRIPT" ] || { echo "missing bronze compat script: $BRONZE_COMPAT_SCRIPT" >&2; exit 1; }

echo "Preparing Sequoia compat-Bronze modern-AMDShared validation boot..."
echo "  target:           $TARGET"
echo "  bronze compat:    $BRONZE_COMPAT_ROOT"
echo "  AMDShared compat: $AMDSHARED_COMPAT_ROOT"
echo "  modern payload:   $MODERN_PAYLOAD_ROOT"
echo

zsh "$SCANOUT_SCRIPT" "$TARGET" "$BRONZE_COMPAT_ROOT" "$AMDSHARED_COMPAT_ROOT" "$MODERN_PAYLOAD_ROOT"
zsh "$AUX_SCRIPT" "$TARGET" "$MODERN_PAYLOAD_ROOT"
zsh "$BRONZE_COMPAT_SCRIPT" "$TARGET" "$BRONZE_COMPAT_ROOT" "$MODERN_PAYLOAD_ROOT"

echo
echo "Validation root prepared."
echo "Next step: boot Sequoia with the eGPU already attached."
echo "Avoid hotplugging on this pass so we don't mix in the separate AMDSupport connector panic."
