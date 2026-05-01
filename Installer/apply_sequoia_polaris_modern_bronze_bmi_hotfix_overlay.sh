#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: apply_sequoia_polaris_modern_bronze_bmi_hotfix_overlay.sh <mounted-system-volume> [modern-polaris-payload-root]

Restore only the real modern 13.5.2 / 4.1.4 AMDMTLBronzeDriver bundle onto an
offline Sequoia volume, then patch the known Ivy Bridge-hostile BMI instruction
sites in AMDMTLBronzeDriverOld.dylib.

Defaults:
  modern-polaris-payload-root  /tmp/oclp-universal/13.5.2

This intentionally updates only:
  - AMDMTLBronzeDriver.bundle

It leaves the current AMDShared choice untouched so we can isolate whether the
WindowServer / dyld failure follows the Bronze plugin load itself.

Run this against an offline Sequoia volume from a stable boot OS such as Big Sur.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 0
fi

TARGET="${1%/}"
MODERN_PAYLOAD_ROOT="${2:-/tmp/oclp-universal/13.5.2}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${TARGET}/Library/Application Support/Kryptonite/RootPatchBackups/${TS}-polaris-modern-bronze-bmi-hotfix"
BRONZE_REL="System/Library/Extensions/AMDMTLBronzeDriver.bundle"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

require_dir() {
  local path="$1"
  [ -d "$path" ] || fail "missing directory: $path"
}

require_item() {
  local root="$1"
  local rel="$2"
  [ -e "${root}/${rel}" ] || fail "missing source item: ${root}/${rel}"
}

bundle_version_summary() {
  local root="$1"
  local rel="$2"
  local info_plist="${root}/${rel}/Contents/Info.plist"
  if [ -f "$info_plist" ]; then
    local short_ver bundle_ver
    short_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
    bundle_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)"
    printf ' (%s / %s)' "${short_ver:-?}" "${bundle_ver:-?}"
  fi
}

kmutil_supports_flag() {
  local flag="$1"
  kmutil install --help 2>/dev/null | grep -q -- "$flag"
}

find_codesign_allocate() {
  local candidate=""

  if [ -n "${CODESIGN_ALLOCATE:-}" ] && [ -x "${CODESIGN_ALLOCATE}" ]; then
    printf '%s\n' "${CODESIGN_ALLOCATE}"
    return 0
  fi

  for candidate in \
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate" \
    "/Volumes/Sonoma/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate" \
    "/Volumes/BigSur/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

resign_bundle_adhoc_deep() {
  local bundle="$1"
  local allocate=""
  allocate="$(find_codesign_allocate)" || fail "could not locate codesign_allocate; install Xcode or export CODESIGN_ALLOCATE"
  CODESIGN_ALLOCATE="$allocate" codesign --force --sign - --timestamp=none --deep "$bundle"
}

normalize_bundle_ownership() {
  local bundle="$1"
  /usr/sbin/chown -R 0:0 "$bundle"
}

verify_bundle_signature() {
  local bundle="$1"
  codesign --verify --deep --strict --verbose=4 "$bundle" >/dev/null
}

remount_target_rw() {
  info "Attempting to remount target read/write..."
  if mount -uw "$TARGET" 2>/dev/null; then
    info "  remounted ${TARGET} read/write"
  else
    fail "could not remount ${TARGET} read/write"
  fi

  if [ ! -w "${TARGET}/System/Library/Extensions" ]; then
    fail "${TARGET}/System/Library/Extensions is still not writable after remount"
  fi
}

backup_and_replace() {
  local source_root="$1"
  local rel="$2"
  local src="${source_root}/${rel}"
  local dst="${TARGET}/${rel}"
  local bkp="${BACKUP_ROOT}/${rel}"

  require_item "$source_root" "$rel"
  mkdir -p "$(dirname "$bkp")" "$(dirname "$dst")"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    ditto "$dst" "$bkp"
    rm -rf "$dst"
  fi

  ditto "$src" "$dst"
}

apply_bronze_binary_patches() {
  local bronze_old="${TARGET}/${BRONZE_REL}/Contents/MacOS/AMDMTLBronzeDriverOld.dylib"

  [ -f "$bronze_old" ] || fail "missing patched target: $bronze_old"

  /usr/bin/perl - "$bronze_old" <<'PERL'
use strict;
use warnings;

sub hex_to_bytes {
  my ($hex) = @_;
  return pack('H*', $hex);
}

my @patches = (
  [
    0xD7E33,
    hex_to_bytes('48b9c3f5285c8fc2f528c4e2ebf6d148c1ea02'),
    hex_to_bytes('b91900000089d031d2f7f189c2909090909090'),
    'amdMtlBronzeInitHwInfo hotfix #1',
  ],
  [
    0xD7E66,
    hex_to_bytes('c4e2ebf6d148c1ea02'),
    hex_to_bytes('89d031d2f7f189c290'),
    'amdMtlBronzeInitHwInfo hotfix #2',
  ],
  [
    0xD7E8A,
    hex_to_bytes('c4e2f3f6c9c1e902'),
    hex_to_bytes('89d031d2f7f189c1'),
    'amdMtlBronzeInitHwInfo hotfix #3',
  ],
);

my $path = $ARGV[0];
open my $fh, '+<', $path or die "open $path: $!\n";
binmode $fh;

for my $edit (@patches) {
  my ($off, $expected, $replacement, $label) = @$edit;
  my $current = '';
  seek $fh, $off, 0 or die "$path: seek $label: $!\n";
  read($fh, $current, length($expected)) == length($expected)
    or die "$path: short read $label at " . sprintf('0x%x', $off) . "\n";

  if ($current ne $expected) {
    die sprintf(
      "%s: %s mismatch at 0x%x\nexpected %s\nfound    %s\n",
      $path,
      $label,
      $off,
      unpack('H*', $expected),
      unpack('H*', $current),
    );
  }

  seek $fh, $off, 0 or die "$path: rewind $label: $!\n";
  print {$fh} $replacement or die "$path: write $label: $!\n";
}

close $fh or die "close $path: $!\n";
PERL
}

rebuild_collections() {
  local -a cmd
  cmd=(
    kmutil install
    --volume-root "$TARGET"
    --update-all
    --force
    --variant-suffix release
  )

  if kmutil_supports_flag '--update-preboot'; then
    cmd+=(--update-preboot)
  fi

  if kmutil_supports_flag '--no-authorization'; then
    cmd+=(--no-authorization)
  fi

  if kmutil_supports_flag '--allow-missing-kdk'; then
    cmd+=(--allow-missing-kdk)
  fi

  info
  info "Rebuilding target kernel collections:"
  printf '  %q' "${cmd[@]}"
  printf '\n'
  "${cmd[@]}"
}

create_root_snapshot() {
  info
  info "Creating new APFS root snapshot for ${TARGET}..."
  bless --mount "$TARGET" --bootefi --create-snapshot
}

require_dir "$TARGET"
require_dir "$MODERN_PAYLOAD_ROOT"
require_item "$MODERN_PAYLOAD_ROOT" "$BRONZE_REL"

[ -e "${TARGET}/System/Library/Extensions/AppleIntelFramebufferCapri.kext" ] || fail "target is missing AppleIntelFramebufferCapri.kext"
[ -e "${TARGET}/System/Library/Extensions/AppleIntelHD4000Graphics.kext" ] || fail "target is missing AppleIntelHD4000Graphics.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDRadeonX4000.kext" ] || fail "target is missing AMDRadeonX4000.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDRadeonX4000HWServices.kext" ] || fail "target is missing AMDRadeonX4000HWServices.kext"
[ -e "${TARGET}/System/Library/Extensions/AMDShared.bundle" ] || fail "target is missing AMDShared.bundle"

mkdir -p "$BACKUP_ROOT"

info "Target root:    ${TARGET}"
info "Modern payload: ${MODERN_PAYLOAD_ROOT}"
info "Backup root:    ${BACKUP_ROOT}"
info "Modern Bronze source:"
info "  ${BRONZE_REL}$(bundle_version_summary "$MODERN_PAYLOAD_ROOT" "$BRONZE_REL")"

remount_target_rw

info
info "Restoring modern Bronze Metal bundle..."
backup_and_replace "$MODERN_PAYLOAD_ROOT" "$BRONZE_REL"
normalize_bundle_ownership "${TARGET}/${BRONZE_REL}"
info "  restored ${BRONZE_REL}"

info
info "Applying Ivy Bridge BMI hotfixes to modern Bronze Metal userland..."
apply_bronze_binary_patches
info "  patched AMDMTLBronzeDriverOld.dylib"

info
info "Re-signing modified modern Bronze bundle ad-hoc..."
resign_bundle_adhoc_deep "${TARGET}/${BRONZE_REL}"
normalize_bundle_ownership "${TARGET}/${BRONZE_REL}"
verify_bundle_signature "${TARGET}/${BRONZE_REL}"
info "  re-signed AMDMTLBronzeDriver.bundle"

rebuild_collections
create_root_snapshot

info
info "Modern Bronze BMI hotfix overlay complete."
