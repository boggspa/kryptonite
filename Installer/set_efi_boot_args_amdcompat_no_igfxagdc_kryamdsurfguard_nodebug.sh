#!/bin/zsh

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <config.plist>" >&2
  exit 1
fi

CFG="$1"
PB="/usr/libexec/PlistBuddy"
GUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
KEY=":NVRAM:Add:${GUID}:boot-args"
ARGS="-lilubetaall ipc_control_port_options=0 -nokcmismatchpanic -lilubeta -krybeta krygpu=AMD krytbtv=1 kryskipagdc=1 kryamdlink=1 kryamdfbval=1 kryamdcompat=1 kryamdsurfguard=1"

[ -f "$CFG" ] || {
  echo "missing config: $CFG" >&2
  exit 1
}

cp "$CFG" "$CFG.backup-$(date +%Y%m%d-%H%M%S)-amdcompat-no-igfxagdc-kryamdsurfguard-nodebug"
$PB -c "Delete $KEY" "$CFG" >/dev/null 2>&1 || true
$PB -c "Add $KEY string $ARGS" "$CFG"
$PB -c "Print $KEY" "$CFG"
