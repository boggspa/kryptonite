#!/bin/zsh

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <config.plist> <boot-arg> [boot-arg ...]" >&2
  exit 1
fi

CFG="$1"
shift

PB="/usr/libexec/PlistBuddy"
GUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
KEY=":NVRAM:Add:${GUID}:boot-args"

[ -f "$CFG" ] || {
  echo "missing config: $CFG" >&2
  exit 1
}

CUR="$($PB -c "Print $KEY" "$CFG" 2>/dev/null || true)"

for ARG in "$@"; do
  NAME="${ARG%%=*}"
  NEXT=""
  for TOKEN in $CUR; do
    TOKEN_NAME="${TOKEN%%=*}"
    if [ "$TOKEN_NAME" = "$NAME" ]; then
      continue
    fi
    NEXT="$NEXT $TOKEN"
  done
  CUR="$NEXT $ARG"
done

CUR="$(printf '%s\n' "$CUR" | awk '{$1=$1; print}')"

cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)-bootargs"
$PB -c "Delete $KEY" "$CFG" >/dev/null 2>&1 || true
$PB -c "Add $KEY string $CUR" "$CFG"
$PB -c "Print $KEY" "$CFG"
