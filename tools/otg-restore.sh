#!/bin/sh
# otg-restore.sh — the restore half of otg-host-force.sh as a standalone step,
# for ending a host session over ssh instead of waiting out the timed window.
#
# Tears the dwc2 controller down while it is still a host (orderly HCD
# teardown), clears the GRF iddig override so ID follows the pin again, probes
# dwc2 afresh (a fresh probe sees a B-device and starts the gadget), then makes
# sure the configfs gadget is attached and adbd is running.
#
# ssh arrives through the dock on the very port being torn down, so the ssh
# session dies at the unbind. Launch it detached and read the log afterwards:
#
#   ssh root@<cabinet> 'setsid nohup sh /userdata/otg-restore.sh </dev/null >/dev/null 2>&1 & sleep 2; ps | grep [o]tg-restore'
#     -> ssh drops within ~10 s; wait another 15 s
#     -> unplug the dock, plug the Linux host back in
#   adb pull /userdata/otg-restore.log
#
# No dwc2 register reads between unbind and bind: the driver gates the clocks
# on remove and an unclocked bus access can hang the SoC.

LOG=/userdata/otg-restore.log
CFG_UDC=/sys/kernel/config/usb_gadget/rockchip/UDC
DWC2_DRV=/sys/bus/platform/drivers/dwc2
DWC2_DEV=10180000.usb
GOTGCTL=0x10180000; GUSBCFG=0x1018000c; GINTSTS=0x10180014
GRF_CON0=0x2000817c; GRF_STAT=0x2000814c
GRACE=${1:-5}   # seconds to wait before touching anything, so ssh can return

log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"; sync; }
snap() { printf -- '--- %s\n' "$1" >>"$LOG"; shift; "$@" >>"$LOG" 2>&1; sync; }
rd() { devmem "$1" 32; }
regs() {
    g=$(rd $GOTGCTL); u=$(rd $GUSBCFG); i=$(rd $GINTSTS); c=$(rd $GRF_CON0); s=$(rd $GRF_STAT)
    printf '  GOTGCTL=%s GUSBCFG=%s GINTSTS=%s GRF_CON0=%s GRF_STAT=%s | CurMod=%s ConIDSts=%s utmi_iddig=%s bvalid=%s\n' \
        "$g" "$u" "$i" "$c" "$s" $(( i & 1 )) $(( (g >> 16) & 1 )) $(( (s >> 8) & 1 )) $(( (s >> 5) & 1 ))
}
usb_tree() {
    for d in /sys/bus/usb/devices/*; do
        [ -r "$d/idVendor" ] || continue
        printf '  %s %s:%s %s / %s  speed=%s driver=%s\n' "$(basename "$d")" \
            "$(cat "$d/idVendor")" "$(cat "$d/idProduct")" \
            "$(cat "$d/manufacturer" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)" \
            "$(cat "$d/speed" 2>/dev/null)" \
            "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"
    done
}
gadget() { printf 'UDC=%s state=%s\n' "$(cat $CFG_UDC 2>&1)" "$(cat /sys/class/android_usb/android0/state 2>&1)"; }

: >"$LOG"
log "otg-restore start  kernel $(uname -r) uptime $(cut -d' ' -f1 /proc/uptime) grace=${GRACE}s"
snap "regs before" regs
snap "usb tree before" usb_tree
snap "gadget before" gadget
if [ "$(( $(rd $GINTSTS) & 1 ))" != "1" ]; then
    log "CurMod=0: controller is not in host mode; nothing to restore"; exit 0
fi
[ -e "$DWC2_DRV/$DWC2_DEV" ] || { log "dwc2 is not bound to $DWC2_DEV; refusing to continue"; exit 1; }

sleep "$GRACE"

# 1. drives off the bus cleanly
for m in /media/usb*; do
    grep -q " $m " /proc/mounts || continue
    if umount "$m" 2>>"$LOG"; then log "unmounted $m"; else umount -l "$m" 2>>"$LOG" && log "lazy-unmounted $m (busy)"; fi
done
sync

# 2. orderly teardown of the host stack, then ID back to the pin
log "unbinding dwc2 platform driver (ssh dies here)"
echo "$DWC2_DEV" >"$DWC2_DRV/unbind" 2>>"$LOG"
sleep 1
if [ -e "$DWC2_DRV/$DWC2_DEV" ]; then log "unbind did not take; aborting before the GRF flip"; exit 1; fi
log "dwc2 unbound"
snap "usb tree after unbind" usb_tree
devmem $GRF_CON0 32 0x06000000
log "GRF iddig override cleared (ID back to pin)"
sleep 2

# 3. fresh probe
log "binding dwc2 platform driver"
echo "$DWC2_DEV" >"$DWC2_DRV/bind" 2>>"$LOG"
sleep 3
if [ ! -e "$DWC2_DRV/$DWC2_DEV" ]; then
    log "dwc2 did NOT rebind — port is dead until power-cycle; skipping register reads"
    snap "dmesg tail" sh -c 'dmesg | tail -n 20'
    exit 1
fi
log "dwc2 bound"
snap "regs after reprobe" regs

# 4. gadget back on the UDC. On 4.19 the configfs driver is parked on a pending
#    list when its UDC vanishes and rebinds by itself when the UDC returns; an
#    explicit write then fails with EBUSY, so only write if it is empty.
snap "gadget after reprobe" gadget
if [ -z "$(cat $CFG_UDC 2>/dev/null)" ]; then
    log "UDC empty: attaching gadget"
    echo "$DWC2_DEV" >"$CFG_UDC" 2>>"$LOG" || { echo "" >"$CFG_UDC" 2>>"$LOG"; echo "$DWC2_DEV" >"$CFG_UDC" 2>>"$LOG"; }
    sleep 2
else
    log "UDC already set ($(cat $CFG_UDC)): gadget re-attached on its own"
fi
ps | grep -q "[a]dbd" || { log "adbd not running; restarting"; start-stop-daemon --start --quiet --background --exec /usr/bin/adbd 2>>"$LOG"; }

# 5. watch for the host to come back (Linux host plugged in after the swap)
t=0; prev=""
while [ $t -lt 90 ]; do
    sleep 5; t=$((t + 5))
    cur="$(gadget) $(regs)"
    [ "$cur" != "$prev" ] && { log "t=${t}s"; echo "$cur" >>"$LOG"; prev=$cur; }
    case "$(cat /sys/class/android_usb/android0/state 2>/dev/null)" in CONFIGURED) log "gadget CONFIGURED at t=${t}s: host enumerated us"; break ;; esac
done
snap "gadget final" gadget
snap "dmesg tail" sh -c 'dmesg | tail -n 25'
log "done"
exit 0
