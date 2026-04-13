#!/bin/bash
# patch_sequoia_applegva_polaris.sh
# Fixes VideoToolbox H.264/HEVC hardware decoding on Ivy Bridge + Polaris
# by explicitly forcing AppleGVA to use the AMD hardware decoder instead of the missing Intel VAD.

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

VOLUME="${1:-/}"
if [ "$VOLUME" = "/" ]; then
    echo "Targeting active root volume."
else
    echo "Targeting volume: $VOLUME"
fi
if ! touch "$VOLUME/.write_test" 2>/dev/null; then
    echo "Volume $VOLUME is read-only. Attempting to remount via device node..."
    DEV=$(diskutil info "$VOLUME" | grep "Device Node" | awk '{print $NF}')
    if [ -n "$DEV" ]; then
        echo "Found device $DEV. Unmounting..."
        diskutil unmount force "$VOLUME" || true
        mkdir -p "$VOLUME"
        echo "Mounting $DEV to $VOLUME as read-write..."
        mount -t apfs "$DEV" "$VOLUME" || mount -uw "$VOLUME" || true
    else
        mount -uw "$VOLUME" 2>/dev/null || true
    fi
else
    rm "$VOLUME/.write_test" 2>/dev/null || true
    echo "Volume is already writable."
fi


GVA_BIN="${VOLUME}/System/Library/PrivateFrameworks/AppleGVA.framework/Versions/A/AppleGVA"
GVA_BUNDLE="${VOLUME}/System/Library/PrivateFrameworks/AppleGVA.framework"
DEFAULTS_PLIST="${VOLUME}/Library/Preferences/com.apple.AppleGVA.plist"
BACKUP_DIR="${VOLUME}/Users/Shared/applegva_patch_backup_$(date +%Y%m%d-%H%M%S)"

# Remove double slashes
GVA_BIN=$(echo "$GVA_BIN" | sed 's://:/:g')
GVA_BUNDLE=$(echo "$GVA_BUNDLE" | sed 's://:/:g')
DEFAULTS_PLIST=$(echo "$DEFAULTS_PLIST" | sed 's://:/:g')
BACKUP_DIR=$(echo "$BACKUP_DIR" | sed 's://:/:g')

if [ ! -f "$GVA_BIN" ]; then
    echo "Error: AppleGVA binary not found at $GVA_BIN"
    echo "Make sure OCLP or the recovery payload has installed the base AppleGVA first."
    exit 1
fi

# 1. Get the current host's board-id
HOST_BOARD_ID=$(ioreg -l | grep "board-id" | awk -F\" '{print $4}' | head -n 1)
if [ -z "$HOST_BOARD_ID" ]; then
    echo "Error: Could not determine host board-id from ioreg!"
    exit 1
fi
echo "Host board-id detected as: $HOST_BOARD_ID"

# Check length - must be exactly 20 chars like Mac-27AD2F918AE68F61
if [ "${#HOST_BOARD_ID}" -ne 20 ]; then
    echo "Error: board-id is not 20 characters (${#HOST_BOARD_ID}). Hex patch requires exact byte match."
    # If this ever happens, we pad it with nulls, but 2012+ Macs are exactly 20.
    exit 1
fi

echo "=== Step 1: Backup ==="
mkdir -p "$BACKUP_DIR"
cp "$GVA_BIN" "$BACKUP_DIR/AppleGVA.binary.orig"
echo "Backup written to: $BACKUP_DIR/AppleGVA.binary.orig"

echo "=== Step 2: Binary patch AppleGVA to spoof MacPro7,1 profile ==="
# We replace the MacPro7,1 board-id string inside the binary with the host's board-id.
# This forces AppleGVA to use the AMD-only MacPro7,1 hardware decoding paths for this Ivy Bridge Mac!
export GVA_BIN_PATH="$GVA_BIN"
export HOST_BOARD_ID="$HOST_BOARD_ID"

python3 -c "
import sys, os
path = os.environ.get('GVA_BIN_PATH', '')
host_id = os.environ.get('HOST_BOARD_ID', '').encode('utf-8')
macpro_id = b'Mac-27AD2F918AE68F61'

if len(host_id) != 20 or len(macpro_id) != 20:
    print('Length mismatch!')
    sys.exit(1)

with open(path, 'rb') as f:
    data = f.read()

count = data.count(macpro_id)
if count == 0:
    print('MacPro7,1 string not found. Maybe already patched or wrong AppleGVA version.')
    if data.count(host_id) > 0:
        print('Host board-id found, binary is likely already patched!')
        sys.exit(0)
    sys.exit(2)

data = data.replace(macpro_id, host_id)

with open(path, 'wb') as f:
    f.write(data)

print(f'Successfully replaced {count} occurrences of {macpro_id.decode()} with {host_id.decode()}!')
"
PY_EXIT=$?
if [ $PY_EXIT -eq 1 ]; then
    echo "Python script failed."
    exit 1
elif [ $PY_EXIT -eq 2 ]; then
    echo "Warning: No patch was applied (string not found)."
fi

echo "=== Step 3: Resign AppleGVA (ad-hoc) ==="
codesign --force --sign - "$GVA_BUNDLE"
echo "Resign complete."

echo "=== Step 4: Inject Global Defaults for Polaris AMD VideoToolbox ==="
# We write directly to the Plist to ensure it applies to the target volume
defaults write "${DEFAULTS_PLIST%.plist}" forceATI -bool yes
defaults write "${DEFAULTS_PLIST%.plist}" gvaForceAMDKE -bool yes
defaults write "${DEFAULTS_PLIST%.plist}" gvaForceAMDAVC -bool yes
defaults write "${DEFAULTS_PLIST%.plist}" gvaForceAMDHEVC -bool yes
defaults write "${DEFAULTS_PLIST%.plist}" gvaForceAMDAVCDecode -bool yes
defaults write "${DEFAULTS_PLIST%.plist}" gvaForceAMDHEVCDecode -bool yes

chmod 644 "$DEFAULTS_PLIST" || true
chown root:wheel "$DEFAULTS_PLIST" || true

echo "Checking the applied overrides:"
defaults read "${DEFAULTS_PLIST%.plist}" | grep -E "forceATI|gvaForce"

echo "=== Final Verification ==="
codesign -dv "$GVA_BUNDLE" 2>&1 | grep -E 'Identifier|Signed Time|TeamIdentifier' || true

echo "Done! AppleGVA has been patched for AMD VideoToolbox acceleration."
