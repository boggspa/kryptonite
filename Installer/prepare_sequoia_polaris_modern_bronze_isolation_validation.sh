#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: prepare_sequoia_polaris_modern_bronze_isolation_validation.sh <mounted-system-volume> <efi-config-plist> [bronze-compat-root] [amdshared-compat-root] [modern-polaris-payload-root]

Prepare a single validation boot that isolates the modern Bronze Metal bundle:
  1. restore the known-good compat Polaris baseline
  2. refresh the Polaris AuxKC accelerator staging
  3. overlay only the modern 13.5.2 Bronze bundle with the Ivy Bridge BMI hotfix
  4. add amfi_get_out_of_my_way=0x1 to OpenCore boot-args

Defaults:
  bronze-compat-root         /tmp/oclp-universal/12.5-23
  amdshared-compat-root      /tmp/oclp-universal/12.5
  modern-polaris-payload-root /tmp/oclp-universal/13.5.2

Run this from a stable helper OS such as Big Sur, against an offline Sequoia
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
SCANOUT_SCRIPT="${SCRIPT_DIR}/apply_sequoia_polaris_scanout_align_overlay.sh"
AUX_SCRIPT="${SCRIPT_DIR}/enable_sequoia_polaris_accel_kc.sh"
BRONZE_SCRIPT="${SCRIPT_DIR}/apply_sequoia_polaris_modern_bronze_bmi_hotfix_overlay.sh"
DISABLE_SCRIPT="${SCRIPT_DIR}/disable_efi_amfi_lv_validation.sh"
GUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
BOOTARGS_KEY=":NVRAM:Add:${GUID}:boot-args"
CSR_KEY=":NVRAM:Add:${GUID}:csr-active-config"
AMFI_ARG="amfi_get_out_of_my_way=0x1"

[ -d "$TARGET" ] || { echo "missing target root: $TARGET" >&2; exit 1; }
[ -f "$CFG" ] || { echo "missing config.plist: $CFG" >&2; exit 1; }
[ -f "$SCANOUT_SCRIPT" ] || { echo "missing scanout baseline script: $SCANOUT_SCRIPT" >&2; exit 1; }
[ -f "$AUX_SCRIPT" ] || { echo "missing aux prep script: $AUX_SCRIPT" >&2; exit 1; }
[ -f "$BRONZE_SCRIPT" ] || { echo "missing Bronze overlay script: $BRONZE_SCRIPT" >&2; exit 1; }
[ -f "$DISABLE_SCRIPT" ] || { echo "missing disable helper: $DISABLE_SCRIPT" >&2; exit 1; }

current_bootargs="$(
  /usr/libexec/PlistBuddy -c "Print ${BOOTARGS_KEY}" "$CFG" 2>/dev/null || true
)"
current_csr_hex="$(
  /usr/libexec/PlistBuddy -c "Print ${CSR_KEY}" "$CFG" 2>/dev/null \
    | /usr/bin/perl -ne 'if (/([0-9A-Fa-f]{8})/) { print lc $1; exit 0 }' || true
)"
current_csr_value="$(
  /usr/bin/perl -e '
    my $hex = shift // "";
    if ($hex =~ /^[0-9a-fA-F]{8}$/) {
      my $value = unpack("V", pack("H*", $hex));
      printf "0x%X", $value;
    }
  ' "$current_csr_hex"
)"

echo "Preparing Sequoia modern Bronze isolation validation boot..."
echo "  target:          $TARGET"
echo "  config:          $CFG"
echo "  bronze compat:   $BRONZE_COMPAT_ROOT"
echo "  AMDShared compat: $AMDSHARED_COMPAT_ROOT"
echo "  modern payload:  $MODERN_PAYLOAD_ROOT"
echo
echo "Current EFI boot-args:"
echo "  ${current_bootargs:-"(missing)"}"
echo "Current EFI csr-active-config bytes:"
echo "  ${current_csr_hex:-"(missing)"}${current_csr_value:+ (${current_csr_value})}"
echo

if [ -n "$current_csr_hex" ] && ! /usr/bin/perl -e '
  my $hex = shift // "";
  exit 1 unless $hex =~ /^[0-9a-fA-F]{8}$/;
  my $value = unpack("V", pack("H*", $hex));
  my $has_lv_exception = (($value & 0x1) != 0) ? 1 : 0;
  exit($has_lv_exception ? 0 : 1);
' "$current_csr_hex"; then
  echo "Warning: csr-active-config does not include SIP bit 0x1."
  echo "         The Library Validation test may still fail even with ${AMFI_ARG}."
  echo
fi

zsh "$SCANOUT_SCRIPT" "$TARGET" "$BRONZE_COMPAT_ROOT" "$AMDSHARED_COMPAT_ROOT" "$MODERN_PAYLOAD_ROOT"
zsh "$AUX_SCRIPT" "$TARGET" "$MODERN_PAYLOAD_ROOT"
zsh "$BRONZE_SCRIPT" "$TARGET" "$MODERN_PAYLOAD_ROOT"

echo
echo "Enabling temporary AMFI boot-arg for this validation pass..."
updated_bootargs=""
for token in ${=current_bootargs}; do
  token_name="${token%%=*}"
  if [ "$token_name" = "${AMFI_ARG%%=*}" ]; then
    continue
  fi
  updated_bootargs="${updated_bootargs} ${token}"
done
updated_bootargs="${updated_bootargs} ${AMFI_ARG}"
updated_bootargs="$(printf '%s\n' "$updated_bootargs" | awk '{$1=$1; print}')"

cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)-bootargs"
/usr/libexec/PlistBuddy -c "Delete ${BOOTARGS_KEY}" "$CFG" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add ${BOOTARGS_KEY} string ${updated_bootargs}" "$CFG"
/usr/libexec/PlistBuddy -c "Print ${BOOTARGS_KEY}" "$CFG"

echo
echo "Validation boot prepared."
echo "Rollback boot-arg when finished:"
echo "  zsh ${DISABLE_SCRIPT} \"$CFG\""
