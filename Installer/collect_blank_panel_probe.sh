#!/bin/zsh

set -euo pipefail

OUT_ROOT="${1:-$HOME/Desktop}"
TS="$(date +%Y%m%d-%H%M%S)"
HOST="$(scutil --get ComputerName 2>/dev/null || hostname)"
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
OUT_DIR="${OUT_ROOT%/}/Kryptonite-BlankPanelProbe-${TS}-${OS_VER}-${BUILD_VER}"

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
Kryptonite blank panel probe bundle

Host: ${HOST}
OS: ${OS_VER} (${BUILD_VER})
Timestamp: ${TS}

Capture this while:
- Sequoia is logged in
- eGPU is connected
- external monitor is online but physically blank
- remote observation is optional, but note whether it is active

Files:
- boot-args.txt
- kmutil-loaded.txt
- kmutil-loaded-aux.txt
- kmutil-loaded-graphics.txt
- displays.txt
- pci.txt
- thunderbolt.txt
- ioreg-ioframebuffer.txt
- ioreg-graphics-stack.txt
- ioreg-iodisplayconnect.txt
- ioreg-yelcho.txt
- ioreg-amdframebuffer.txt
- ioreg-amd9500-wrangler.txt
- ioreg-ati-device-control.txt
- ioreg-amd-accel.txt
- ioreg-amd-hwservices.txt
- ioreg-capri.txt
- log-kernel-display-last-boot.txt
- log-windowserver-last-15m.txt
- log-windowserver-surface-last-15m.txt
EOF

run_capture boot-args nvram -p
run_capture kmutil-loaded kmutil showloaded
run_capture kmutil-loaded-aux kmutil showloaded --collection aux --show all
run_capture kmutil-loaded-graphics /bin/zsh -lc "kmutil showloaded --collection aux --show all | grep -Ei 'AppleIntelFramebufferCapri|AppleIntelHD4000Graphics|AMDRadeonX4000|AMDRadeonX4000HWServices|AMDRadeonX4000HWLibs' ; echo ; kmutil showloaded | grep -Ei 'AMDSupport|AMD10000Controller|AMD9500Controller|AMDFramebuffer|Kryptonite'"
run_capture displays system_profiler SPDisplaysDataType
run_capture pci system_profiler SPPCIDataType
run_capture thunderbolt system_profiler SPThunderboltDataType
run_capture ioreg-ioframebuffer ioreg -lw0 -r -c IOFramebuffer
run_capture ioreg-graphics-stack /bin/zsh -lc "ioreg -lw0 | grep -Ei 'AMDRadeonX4000|AMDFramebuffer|AMD9500Controller|AppleIntelFramebufferCapri|AppleIntelHD4000Graphics|IOAccel|Display_boot|Color LCD|2270W' || true"
run_capture ioreg-iodisplayconnect ioreg -lw0 -r -c IODisplayConnect
run_capture ioreg-yelcho ioreg -lw0 -r -n ATY,Yelcho
run_capture ioreg-amdframebuffer ioreg -lw0 -r -c AMDFramebuffer
run_capture ioreg-amd9500-wrangler ioreg -lw0 -r -n AMD9500ControllerWrangler
run_capture ioreg-ati-device-control ioreg -lw0 -r -n AtiDeviceControl
run_capture ioreg-amd-accel ioreg -lw0 -r -n AMDRadeonX4000_AMDEllesmereGraphicsAccelerator
run_capture ioreg-amd-hwservices ioreg -lw0 -r -n AMDRadeonX4000_AMDRadeonHWServicesPolaris
run_capture ioreg-capri ioreg -lw0 -r -n AppleIntelFramebufferCapri
run_capture log-kernel-display-last-boot /usr/bin/log show --last boot --style syslog --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "AMD" OR eventMessage CONTAINS[c] "ATY" OR eventMessage CONTAINS[c] "display" OR eventMessage CONTAINS[c] "framebuffer" OR eventMessage CONTAINS[c] "IOAccel" OR eventMessage CONTAINS[c] "AGDC" OR eventMessage CONTAINS[c] "Kryptonite")'
run_capture log-windowserver-last-15m /usr/bin/log show --last 15m --style syslog --predicate '(process == "WindowServer" OR process == "kernel") AND (eventMessage CONTAINS[c] "AMD" OR eventMessage CONTAINS[c] "display" OR eventMessage CONTAINS[c] "framebuffer" OR eventMessage CONTAINS[c] "IOAccel" OR eventMessage CONTAINS[c] "AGDC" OR eventMessage CONTAINS[c] "Kryptonite" OR eventMessage CONTAINS[c] "Yelcho")'
run_capture log-windowserver-surface-last-15m /usr/bin/log show --last 15m --style syslog --predicate '(process == "WindowServer" OR process == "kernel" OR process == "Dock") AND (eventMessage CONTAINS[c] "Surface mode" OR eventMessage CONTAINS[c] "display pipe" OR eventMessage CONTAINS[c] "IOSurface" OR eventMessage CONTAINS[c] "CoreDisplay" OR eventMessage CONTAINS[c] "SkyLight" OR eventMessage CONTAINS[c] "window" OR eventMessage CONTAINS[c] "wallpaper")'

printf '%s\n' "$OUT_DIR"
