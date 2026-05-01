#!/bin/zsh

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <config.plist> <boot-arg-token>" >&2
  exit 1
fi

CFG="$1"
TOKEN="$2"
PB="/usr/libexec/PlistBuddy"
GUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
KEY=":NVRAM:Add:${GUID}:boot-args"

[ -f "$CFG" ] || {
  echo "missing config: $CFG" >&2
  exit 1
}

CURRENT="$($PB -c "Print $KEY" "$CFG" 2>/dev/null || true)"

if [ -z "$CURRENT" ]; then
  echo "boot-args entry missing, nothing to remove"
  exit 0
fi

typeset -a TOKENS
TOKENS=(${=CURRENT})

typeset -a FILTERED
FILTERED=()

removed=0
for item in "${TOKENS[@]}"; do
  if [ "$item" = "$TOKEN" ]; then
    removed=1
    continue
  fi
  FILTERED+=("$item")
done

if [ "$removed" -eq 0 ]; then
  echo "token not present: $TOKEN"
  echo "$CURRENT"
  exit 0
fi

NEW_ARGS="${(j: :)FILTERED}"

cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)-remove-boot-arg"
$PB -c "Delete $KEY" "$CFG" >/dev/null 2>&1 || true
$PB -c "Add $KEY string $NEW_ARGS" "$CFG"
$PB -c "Print $KEY" "$CFG"
