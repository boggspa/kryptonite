#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: stash_sequoia_polaris_root_payload.sh <mounted-system-volume> [stash-dir]

Copies the exact OCLP Polaris root-patch payload from the mounted Sequoia
system volume into a reusable stash directory so it can later be overlaid onto
an Intel-stable Sequoia installation.

Default stash directory:
  ~/Desktop/Kryptonite-Polaris-Stash-<timestamp>
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
TS="$(date +%Y%m%d-%H%M%S)"
STASH="${2:-${HOME}/Desktop/Kryptonite-Polaris-Stash-${TS}}"
PATCHSET_PLIST="${TARGET}/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist"

typeset -a PAYLOAD_ITEMS
PAYLOAD_ITEMS=(
  "System/Library/Frameworks/OpenCL.framework"
  "System/Library/Frameworks/OpenGL.framework"
  "System/Library/Extensions/AMDMTLBronzeDriver.bundle"
  "System/Library/Extensions/AMDRadeonVADriver2.bundle"
  "System/Library/Extensions/AMDRadeonX4000.kext"
  "System/Library/Extensions/AMDRadeonX4000GLDriver.bundle"
  "System/Library/Extensions/AMDRadeonX4000HWServices.kext"
  "System/Library/Extensions/AMDShared.bundle"
)

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

[ -d "$TARGET" ] || fail "missing target root: $TARGET"
[ -f "$PATCHSET_PLIST" ] || fail "missing OCLP patch manifest: $PATCHSET_PLIST"

mkdir -p "$STASH"

if plutil -p "$PATCHSET_PLIST" 2>/dev/null | grep -q '"AMD Polaris"'; then
  info "Patch manifest reports AMD Polaris"
else
  info "Patch manifest does not report AMD Polaris; falling back to on-disk payload inspection"
fi

for rel in "${PAYLOAD_ITEMS[@]}"; do
  src="${TARGET}/${rel}"
  dst="${STASH}/${rel}"
  [ -e "$src" ] || fail "missing payload item: $src"
  mkdir -p "$(dirname "$dst")"
  ditto "$src" "$dst"
done

cp "$PATCHSET_PLIST" "${STASH}/OpenCore-Legacy-Patcher.plist"

{
  echo "target=${TARGET}"
  echo "time=${TS}"
  echo "patch_manifest=${PATCHSET_PLIST}"
  echo
  echo "[payload]"
  for rel in "${PAYLOAD_ITEMS[@]}"; do
    echo "$rel"
  done
} > "${STASH}/manifest.txt"

info "Stashed Polaris root payload to:"
info "  ${STASH}"
