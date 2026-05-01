#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: disable_efi_amfi_lv_validation.sh <efi-config-plist>

Remove the temporary AMFI Library Validation boot-arg that was added for the
modern Polaris userland validation boot.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 1 ]; then
  usage
  exit 0
fi

CFG="$1"
GUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
BOOTARGS_KEY=":NVRAM:Add:${GUID}:boot-args"
AMFI_ARG="amfi_get_out_of_my_way=0x1"

[ -f "$CFG" ] || { echo "missing config.plist: $CFG" >&2; exit 1; }

echo "Removing temporary AMFI validation boot-arg..."
current_bootargs="$(
  /usr/libexec/PlistBuddy -c "Print ${BOOTARGS_KEY}" "$CFG" 2>/dev/null || true
)"

if [ -z "$current_bootargs" ]; then
  echo "boot-args entry missing, nothing to remove"
  exit 0
fi

filtered_bootargs=""
removed=0
for token in ${=current_bootargs}; do
  token_name="${token%%=*}"
  if [ "$token_name" = "${AMFI_ARG%%=*}" ]; then
    removed=1
    continue
  fi
  filtered_bootargs="${filtered_bootargs} ${token}"
done

if [ "$removed" -eq 0 ]; then
  echo "token not present: ${AMFI_ARG%%=*}"
  echo "$current_bootargs"
  exit 0
fi

filtered_bootargs="$(printf '%s\n' "$filtered_bootargs" | awk '{$1=$1; print}')"

cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)-remove-boot-arg"
/usr/libexec/PlistBuddy -c "Delete ${BOOTARGS_KEY}" "$CFG" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add ${BOOTARGS_KEY} string ${filtered_bootargs}" "$CFG"
/usr/libexec/PlistBuddy -c "Print ${BOOTARGS_KEY}" "$CFG"

echo
echo "AMFI validation boot-arg removed."
