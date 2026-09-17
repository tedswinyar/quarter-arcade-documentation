#!/bin/sh
# Watch what a device does on the Mac's USB bus. No dependencies.
#
#   ./tools/usbwatch.sh baseline     # with the cabinet UNPLUGGED
#   ./tools/usbwatch.sh check        # after plugging it in
#   ./tools/usbwatch.sh poll         # continuous, for catching brief appearances
#
# What to look for on a Quarter Arcades cabinet:
#   Vendor ID 0x2207 (Fuzhou Rockchip)  -> the SoC's USB gadget or its
#                                          loader/maskrom mode is alive. This is
#                                          the good outcome: it means the port
#                                          does data, and dumping is possible.
#   nothing at all                      -> port is charge-only from Linux's point
#                                          of view, consistent with the device
#                                          tree disabling the OTG PHY port.
#
# Use a cable you have verified carries data — plenty of USB-C cables are
# charge-only, and that failure looks identical to the interesting one.
SNAP=/tmp/usbwatch-baseline.txt

snap() { system_profiler SPUSBDataType 2>/dev/null \
    | grep -E "^ +[A-Za-z0-9].*:$|Product ID|Vendor ID|Serial Number|Manufacturer|Speed" ; }

case "${1:-check}" in
  baseline) snap > "$SNAP"; echo "baseline saved: $(grep -c 'Product ID' "$SNAP") device(s)";;
  check)
    [ -f "$SNAP" ] || { echo "no baseline; run '$0 baseline' unplugged first" >&2; exit 1; }
    snap > /tmp/usbwatch-now.txt
    if diff -u "$SNAP" /tmp/usbwatch-now.txt > /tmp/usbwatch-diff.txt; then
      echo "NO CHANGE — nothing enumerated."
    else
      echo "CHANGE detected:"; grep '^+' /tmp/usbwatch-diff.txt | grep -v '^+++'
      grep -qi "0x2207" /tmp/usbwatch-now.txt && echo "
>>> Rockchip vendor ID 0x2207 present — the port does data."
    fi;;
  poll)
    echo "polling every 2s, ctrl-c to stop"
    last=""
    while :; do
      cur=$(snap | grep -E "Vendor ID|Product ID" | tr -d ' \n')
      [ "$cur" != "$last" ] && { echo "--- $(date +%T)"; snap | grep -E "Vendor ID|Product ID"; last="$cur"; }
      sleep 2
    done;;
  *) sed -n '2,30p' "$0";;
esac
