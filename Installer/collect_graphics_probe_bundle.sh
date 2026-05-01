#!/bin/zsh

set -euo pipefail

OUT_ROOT="${1:-$HOME/Desktop}"
TS="$(date +%Y%m%d-%H%M%S)"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
OUT_DIR="${OUT_ROOT%/}/Kryptonite-GraphicsProbe-${TS}-${OS_VER}-${BUILD_VER}"

mkdir -p "$OUT_DIR"

run_capture() {
  local name="$1"
  shift

  {
    printf '== %s ==\n' "$name"
    printf 'Command:'
    printf ' %q' "$@"
    printf '\n\n'
    "$@" 2>&1
  } > "${OUT_DIR}/${name}.txt"
}

cat > "${OUT_DIR}/README.txt" <<EOF
Kryptonite graphics probe bundle

Host: ${HOST}
OS: ${OS_VER} (${BUILD_VER})
Timestamp: ${TS}

Files:
- boot-args.txt
- kmutil-loaded.txt
- displays.txt
- pci.txt
- ioreg-ioframebuffer.txt
- ioreg-iodisplayconnect.txt
- ioreg-yelcho.txt
- ioreg-capri.txt
- log-kernel-display.txt
EOF

run_capture boot-args nvram -p
run_capture kmutil-loaded kmutil showloaded
run_capture displays system_profiler SPDisplaysDataType
run_capture pci system_profiler SPPCIDataType
run_capture ioreg-ioframebuffer ioreg -lw0 -r -c IOFramebuffer
run_capture ioreg-iodisplayconnect ioreg -lw0 -r -c IODisplayConnect
run_capture ioreg-yelcho ioreg -lw0 -r -n ATY,Yelcho
run_capture ioreg-capri ioreg -lw0 -r -n AppleIntelFramebufferCapri
run_capture log-kernel-display /usr/bin/log show --last boot --style syslog --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "AMD" OR eventMessage CONTAINS[c] "ATY" OR eventMessage CONTAINS[c] "display" OR eventMessage CONTAINS[c] "framebuffer" OR eventMessage CONTAINS[c] "Kryptonite")'

printf '%s\n' "$OUT_DIR"
