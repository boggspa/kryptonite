#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
usage: revert_sequoia_login_ui.sh <mounted-system-volume>

Restores the Sequoia login/UI preference files that were modified by the
temporary minimal-login workaround. If backup files are present, they are
restored. Otherwise only the workaround keys are removed.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 1 ]; then
  usage
  exit 0
fi

ROOT="${1%/}"
PREFS="${ROOT}/Library/Preferences"
LOGIN="${PREFS}/com.apple.loginwindow.plist"
UA="${PREFS}/com.apple.universalaccess.plist"
GLOBAL="${PREFS}/.GlobalPreferences.plist"
TS="$(date +%Y%m%d-%H%M%S)"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

latest_backup() {
  local file="$1"
  local -a matches
  setopt local_options null_glob
  matches=("${file}".backup-*)
  if [ "${#matches[@]}" -eq 0 ]; then
    return 0
  fi
  ls -1t "${matches[@]}" 2>/dev/null | head -1
}

backup_current_if_present() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$file.before-revert-$TS"
  fi
}

restore_or_delete_key() {
  local file="$1"
  local key="$2"
  if [ -f "$file" ]; then
    /usr/bin/defaults delete "$file" "$key" >/dev/null 2>&1 || true
  fi
}

[ -d "$PREFS" ] || fail "missing preferences directory: $PREFS"

info "Target root: ${ROOT}"
info "Preferences: ${PREFS}"

for file in "$LOGIN" "$UA" "$GLOBAL"; do
  backup_current_if_present "$file"
done

login_backup="$(latest_backup "$LOGIN")"
global_backup="$(latest_backup "$GLOBAL")"
ua_backup="$(latest_backup "$UA")"

if [ -n "$login_backup" ]; then
  cp "$login_backup" "$LOGIN"
  info "Restored loginwindow backup: $login_backup"
else
  restore_or_delete_key "$LOGIN" "SHOWFULLNAME"
  restore_or_delete_key "$LOGIN" "Hide500Users"
  restore_or_delete_key "$LOGIN" "RetriesUntilHint"
  info "Removed loginwindow workaround keys"
fi

if [ -n "$global_backup" ]; then
  cp "$global_backup" "$GLOBAL"
  info "Restored global preferences backup: $global_backup"
else
  restore_or_delete_key "$GLOBAL" "AppleReduceDesktopTinting"
  restore_or_delete_key "$GLOBAL" "AppleShowScrollBars"
  info "Removed global workaround keys"
fi

if [ -n "$ua_backup" ]; then
  cp "$ua_backup" "$UA"
  info "Restored universal access backup: $ua_backup"
else
  restore_or_delete_key "$UA" "reduceMotion"
  restore_or_delete_key "$UA" "reduceTransparency"
  restore_or_delete_key "$UA" "increaseContrast"
  info "Removed universal access workaround keys"
fi

info
info "Login/UI workaround reverted for ${ROOT}"
