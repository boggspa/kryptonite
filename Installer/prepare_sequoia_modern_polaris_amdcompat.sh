#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: prepare_sequoia_modern_polaris_amdcompat.sh <mounted-system-volume> <efi-config-plist> [oclp-payload-root]

Restore the last known-stable Sequoia Polaris baseline and set the exact
Kryptonite AMD compatibility boot-args in one pass.

This wrapper:
  1. reapplies the modern OCLP 13.5.2 Polaris overlay
  2. updates OpenCore boot-args to the amdcompat profile

Defaults:
  oclp-payload-root  /tmp/oclp-universal/13.5.2

Run this from a stable boot OS such as Big Sur, against an offline Sequoia
system volume and the EFI config.plist used to boot Sequoia.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
CFG="$2"
PAYLOAD_ROOT="${3:-/tmp/oclp-universal/13.5.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODERN_SCRIPT="${SCRIPT_DIR}/apply_sequoia_oclp_polaris_modern_overlay.sh"
BOOTARGS_SCRIPT="${SCRIPT_DIR}/set_efi_boot_args_amdcompat.sh"

[ -d "$TARGET" ] || { echo "missing target root: $TARGET" >&2; exit 1; }
[ -f "$CFG" ] || { echo "missing config.plist: $CFG" >&2; exit 1; }
[ -f "$MODERN_SCRIPT" ] || { echo "missing modern overlay script: $MODERN_SCRIPT" >&2; exit 1; }
[ -f "$BOOTARGS_SCRIPT" ] || { echo "missing boot-args script: $BOOTARGS_SCRIPT" >&2; exit 1; }

echo "Preparing Sequoia modern Polaris + amdcompat baseline..."
echo "  target:  $TARGET"
echo "  config:  $CFG"
echo "  payload: $PAYLOAD_ROOT"
echo

zsh "$MODERN_SCRIPT" "$TARGET" "$PAYLOAD_ROOT"

echo
echo "Applying exact amdcompat boot-args..."
zsh "$BOOTARGS_SCRIPT" "$CFG"

echo
echo "Preparation complete."
