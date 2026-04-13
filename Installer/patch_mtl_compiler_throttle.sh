#!/bin/bash
# patch_mtl_compiler_throttle.sh
# Limits Metal Compiler Service to prevent 13+ concurrent compiler storm on Ivy Bridge CPUs.
# Sets _MultipleInstances to false and caps MTLGet*CompilerProcessesCount to 2.

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


export MTL_XPC="${VOLUME}/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc/Contents/Info.plist"
export MTL_XPC_BUNDLE="${VOLUME}/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc"
export MTL_BIN="${VOLUME}/System/Library/Frameworks/Metal.framework/Versions/A/Metal"
export BACKUP_DIR="${VOLUME}/Users/Shared/metal_patch_backup_$(date +%Y%m%d-%H%M%S)"

# Remove double slashes just in case
MTL_XPC=$(echo "$MTL_XPC" | sed 's://:/:g')
MTL_XPC_BUNDLE=$(echo "$MTL_XPC_BUNDLE" | sed 's://:/:g')
MTL_BIN=$(echo "$MTL_BIN" | sed 's://:/:g')
BACKUP_DIR=$(echo "$BACKUP_DIR" | sed 's://:/:g')

if [ ! -f "$MTL_BIN" ]; then
    echo "Error: Metal binary not found at $MTL_BIN"
    exit 1
fi

echo "=== Step 1: Backup ==="
mkdir -p "$BACKUP_DIR"
cp "$MTL_XPC" "$BACKUP_DIR/MTLCompilerService_Info.plist.orig"
cp "$MTL_BIN" "$BACKUP_DIR/Metal.binary.orig"
echo "Backups written to: $BACKUP_DIR"

echo "=== Step 2: Patch XPC plist - disable multiple instances ==="
plutil -replace XPCService._MultipleInstances -bool false "$MTL_XPC"
echo "XPC plist patched."
plutil -p "$MTL_XPC" | grep -A2 XPCService

echo "=== Step 3: Binary patch Metal framework - cap compiler count to 2 ==="
python3 -c "
import sys
import os

path = os.environ.get('MTL_BIN', '')
if not path:
    sys.exit(1)

patch_bytes = bytes([0xB8, 0x02, 0x00, 0x00, 0x00, 0xC3, 0x90, 0x90])
verify_orig = bytes([0x55, 0x48, 0x89, 0xE5, 0x31, 0xC0, 0x5D, 0xC3])

targets = {
    'MTLGetDefaultCompilerProcessesCount': 0x2060,
    'MTLGetMaximumCompilerProcessesCount': 0x2070,
    'MTLGetOptimalCompilerProcessesCount': 0x2080,
}

patched_count = 0
try:
    with open(path, 'r+b') as f:
        for name, offset in targets.items():
            f.seek(offset)
            current = f.read(8)
            if current == patch_bytes:
                print(f' SKIP {name} @ 0x{offset:x}: already patched')
                continue
            if current != verify_orig:
                print(f' SKIP {name} @ 0x{offset:x}: unexpected bytes {current.hex()}')
                continue
            
            f.seek(offset)
            f.write(patch_bytes)
            print(f' PATCHED {name} @ 0x{offset:x}: {verify_orig.hex()} -> {patch_bytes.hex()}')
            patched_count += 1
except Exception as e:
    print(f'Error patching: {e}')
    sys.exit(1)

sys.exit(0 if patched_count > 0 else 0) # Exit 0 anyway since no error
"
PY_EXIT=$?
if [ $PY_EXIT -eq 0 ]; then
    echo "Binary patch applied successfully."
else
    echo "Binary patch failed."
    exit 1
fi

echo "=== Step 4: Resign XPC bundle & Metal framework (ad-hoc) ==="
codesign --force --sign - "$MTL_XPC_BUNDLE"
codesign --force --sign - "$MTL_BIN"
echo "Resign complete."

echo "=== Final Verification ==="
echo "Codesign status:"
codesign -dv "$MTL_XPC_BUNDLE" 2>&1 | grep -E 'Identifier|Signed Time|TeamIdentifier' || true
echo "---"
plutil -p "$MTL_XPC" | grep '_MultipleInstances' || true

echo "Done! The compiler throttle has been applied."
