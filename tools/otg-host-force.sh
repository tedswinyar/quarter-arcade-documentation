#!/bin/sh
# otg-host-force.sh — route 1: force the rear USB-C dwc2 into host mode by
# register, since the phy's otg_mode sysfs knob is inert on this unit (the
# phy's otg-port node is disabled in the live DT; "No support otg").
#
# Mechanism A (primary): GRF UOC0_CON0 (0x2000817c) bits 9/10 are the phy's
#   iddig_en / iddig_output overrides — exactly what otg_mode=host would write.
#   Forcing ID low makes the dwc2 core see an A-device connector and raise
#   ConIDStsChng (unmasked: GINTMSK bit 28 = 1); the driver then re-inits as
#   host and starts the HCD.
# Mechanism B (fallback, if CurMod never flips): GUSBCFG (0x1018000c) bit 29
#   ForceHostMode.
# Both are undone at the end; a power-cycle undoes everything regardless.
#
#   adb push tools/otg-host-force.sh /userdata/otg-host-force.sh
#   adb shell '(setsid sh /userdata/otg-host-force.sh 120 240 </dev/null >/dev/null 2>&1 &)'
#     -> within DELAY s: unplug host, plug the self-powered dock (drives in)
#     -> after DELAY+WINDOW s: unplug dock, plug host back, pull the log
#   adb pull /userdata/otg-host-force.log

DELAY=${1:-120}
WINDOW=${2:-240}
STEP=5
LOG=/userdata/otg-host-force.log
CFG_UDC=/sys/kernel/config/usb_gadget/rockchip/UDC

DWC=0x10180000
GOTGCTL=0x10180000; GUSBCFG=0x1018000c; GINTSTS=0x10180014
GRF_CON0=0x2000817c; GRF_STAT=0x2000814c

log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"; }
section() { printf '\n===== %s\n' "$*" >>"$LOG"; }
snap() { printf -- '--- %s\n' "$1" >>"$LOG"; shift; "$@" >>"$LOG" 2>&1; }
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
storage() {
    grep -E ' sd[a-z]' /proc/partitions
    grep -E '/media/|/dev/sd' /proc/mounts
    for m in /media/usb*; do [ -d "$m" ] && [ -n "$(ls -A "$m" 2>/dev/null)" ] && { echo "  $m:"; ls -la "$m" | head -20; }; done
}
curmod() { i=$(rd $GINTSTS); echo $(( i & 1 )); }

: >"$LOG"
log "otg-host-force start  delay=${DELAY}s window=${WINDOW}s  kernel $(uname -r) uptime $(cut -d' ' -f1 /proc/uptime)"
section "baseline"
snap "regs" regs
snap "usb tree" usb_tree
snap "gadget" sh -c "cat $CFG_UDC; cat /sys/class/android_usb/android0/state"
snap "dmesg tail" sh -c 'dmesg | tail -n 5'
ORIG_USBCFG=$(rd $GUSBCFG)
# sshd reads /root/.ssh/authorized_keys; /root is on the read-only squashfs, so
# the persistent copy has to be bind-mounted every boot.
grep -q " /root " /proc/mounts || { mount --bind /userdata/root /root && log "bind-mounted /userdata/root on /root"; }

section "waiting ${DELAY}s for cable swap (unplug host, plug powered dock)"
sleep "$DELAY"
snap "regs before switch" regs

# ---- A: GRF iddig override -> ID low (A-device / host) ----------------------
section "A: GRF iddig override (bit9 iddig_en=1, bit10 iddig_output=0)"
devmem $GRF_CON0 32 0x06000200
sleep 1
snap "regs after GRF write" regs
FORCED_B=0
n=0
while [ $n -lt 6 ]; do
    [ "$(curmod)" = "1" ] && break
    sleep 1; n=$((n + 1))
done
if [ "$(curmod)" = "1" ]; then
    log "CurMod=1: core is in host mode after ${n}s (GRF path worked)"
else
    log "CurMod still 0 after ${n}s -> B: GUSBCFG ForceHostMode"
    u=$(rd $GUSBCFG)
    devmem $GUSBCFG 32 $(( (u & ~(1 << 30)) | (1 << 29) ))
    FORCED_B=1
    sleep 1
    snap "regs after GUSBCFG force" regs
fi
sync

# ---- sample ----------------------------------------------------------------
section "sampling every ${STEP}s for ${WINDOW}s"
prev_tree=""; prev_dmesg=""; prev_stor=""
t=0
while [ "$t" -lt "$WINDOW" ]; do
    sleep "$STEP"; t=$((t + STEP))
    tree=$(usb_tree); dm=$(dmesg | tail -n 15); st=$(storage)
    if [ "$t" = "$STEP" ]; then
        sleep 10
        snap "net (t=15s)" sh -c 'ip link show; ip addr show'
        # Run 3 (2026-09-14): the dock's r8152 NIC enumerated but the switch never
        # learned a MAC — dhcpcd (started at boot) ignored the hot-plugged
        # interface. Bring up every new interface and ask for a lease explicitly.
        for ifp in /sys/class/net/*; do
            ifn=$(basename "$ifp")
            case "$ifn" in lo|eth0|sit0) continue ;; esac
            log "new interface $ifn: bringing up + dhcp"
            ip link set "$ifn" up 2>>"$LOG"
            dhcpcd -n "$ifn" >>"$LOG" 2>&1 || udhcpc -i "$ifn" -b -q -t 5 >>"$LOG" 2>&1
        done
        sleep 8
        snap "net after dhcp" sh -c 'ip addr show; ip route show; cat /etc/resolv.conf 2>/dev/null'
    fi
    changed=""
    [ "$tree" != "$prev_tree" ] && changed="$changed usb"
    [ "$dm" != "$prev_dmesg" ] && changed="$changed dmesg"
    [ "$st" != "$prev_stor" ] && changed="$changed storage"
    if [ -n "$changed" ]; then
        log "t=${t}s changed:$changed"
        regs >>"$LOG"
        [ "$tree" != "$prev_tree" ] && { echo "$tree" >>"$LOG"; prev_tree=$tree; }
        [ "$dm" != "$prev_dmesg" ] && { echo "$dm" | sed 's/^/  | /' >>"$LOG"; prev_dmesg=$dm; }
        [ "$st" != "$prev_stor" ] && { echo "$st" >>"$LOG"; prev_stor=$st; }
        sync
    elif [ $((t % 30)) -eq 0 ]; then
        log "t=${t}s no change"; regs >>"$LOG"; ip addr show 2>/dev/null | grep -E "^[0-9]+:|inet " | grep -v -E " lo:|127.0.0.1" >>"$LOG"
    fi
    # Run 4 (2026-09-15): the dock's NIC came up as eth1 and dhcpcd accepted it,
    # but with no cable in. If there is still no lease a minute in, try udhcpc.
    if [ "$t" = "60" ] && ! ip -4 addr show 2>/dev/null | grep "inet " | grep -qv "127.0.0.1"; then
        for ifp in /sys/class/net/*; do
            ifn=$(basename "$ifp")
            case "$ifn" in lo|eth0|sit0) continue ;; esac
            log "no lease on $ifn after 60s: udhcpc fallback"
            udhcpc -i "$ifn" -n -q -t 8 >>"$LOG" 2>&1
        done
        snap "net after udhcpc" sh -c 'ip -4 addr show; ip route show'
    fi
done

section "end of window"
snap "regs" regs
snap "usb tree" usb_tree
snap "storage" storage

# ---- restore ---------------------------------------------------------------
# Touch /userdata/keep-host (e.g. over ssh once the network is up) to stay in
# host mode; the file is removed so the next boot/run is normal.
if [ -e /userdata/keep-host ]; then
    rm -f /userdata/keep-host; log "keep-host present: staying in host mode, no restore"; sync; exit 0
fi
section "restore"
# Run 2 (2026-09-14): after a real host session the gadget came back
# DISCONNECTED and never re-enumerated; power-cycle needed.
# Run 4 (2026-09-15): clearing the override and rebinding the UDC (configfs)
# left it bound but dead — the host got no descriptor reads. Whatever host mode
# leaves behind in the controller survives a UDC rebind, so tear the whole
# controller down and probe it again: unbind the dwc2 platform driver while
# still in host mode (orderly HCD teardown), flip the ID back, bind (a fresh
# probe sees a B-device and starts the gadget), then reattach configfs.
# No dwc2 register reads between unbind and bind: the driver gates the clocks
# on remove and an unclocked bus access can hang the SoC.
DWC2_DRV=/sys/bus/platform/drivers/dwc2
for m in /media/usb*; do grep -q " $m " /proc/mounts && { umount "$m" && log "unmounted $m"; }; done; sync
[ "$FORCED_B" = "1" ] && { devmem $GUSBCFG 32 $(( ORIG_USBCFG & ~(3 << 29) )); log "GUSBCFG restored to $ORIG_USBCFG"; }
log "unbinding dwc2 platform driver"; sync
echo 10180000.usb >"$DWC2_DRV/unbind" 2>>"$LOG"
log "dwc2 unbound"; snap "usb tree after unbind" usb_tree
devmem $GRF_CON0 32 0x06000000; log "GRF iddig override cleared (ID back to pin)"
sleep 2
log "binding dwc2 platform driver"; sync
echo 10180000.usb >"$DWC2_DRV/bind" 2>>"$LOG"
sleep 3
if [ -e "$DWC2_DRV/10180000.usb" ]; then
    log "dwc2 bound"
    snap "regs after reprobe" regs
    log "attaching gadget to UDC"
    echo 10180000.usb >"$CFG_UDC" 2>>"$LOG"
    sleep 2
else
    log "dwc2 did NOT rebind — port is dead until power-cycle; skipping register reads"
fi
ps | grep -q "[a]dbd" || { log "adbd not running; restarting"; start-stop-daemon --start --quiet --background --exec /usr/bin/adbd 2>>"$LOG"; }
snap "gadget" sh -c "cat $CFG_UDC; cat /sys/class/android_usb/android0/state"
snap "dmesg tail" sh -c 'dmesg | tail -n 15'
log "done — reconnect the Linux host and pull $LOG"
sync
exit 0
