#!/bin/sh
#
# hostmode.sh — boot-time worker for USB host mode on the rear USB-C port.
#
# Launched detached by /etc/init.d/S60hostmode when /userdata/host-mode exists.
# After a short settling delay it bind-mounts /userdata/root on /root (sshd's
# authorized_keys), flips the dwc2 controller to host by overriding the phy's ID
# input in the GRF (the single register write tools/otg-host-force.sh uses), waits
# for a device to enumerate on the port, brings up any new network interface with
# dhcpcd, and leaves the cabinet in host mode.
#
# If nothing enumerates within ENUM_WAIT seconds (no dock, dock without power) it
# runs the restore sequence from tools/otg-restore.sh — unbind the dwc2 platform
# driver, clear the override, bind again — so the port is the adb gadget again and
# the cabinet is reachable the usual way. The flag is left in place; delete it to
# make the next boot a plain one.
#
#   hostmode.sh                      boot-time run; log in /userdata/hostmode.log
#                                    (previous boot's log kept as hostmode.log.1)
#   hostmode.sh --dry-run            log every step, write no register, mount
#                                    nothing, unbind nothing; log goes to
#                                    /userdata/hostmode-dryrun.log
#   hostmode.sh --dry-run --no-hub   as above, but pretend nothing enumerated so
#                                    the fallback branch is exercised as well
#
# Register and sequence provenance: docs/14. Rules carried over from the two
# tools this is derived from: mechanism A only (no GUSBCFG ForceHostMode), and no
# dwc2 register reads between the driver unbind and the bind, because the driver
# gates the controller clocks on remove and an unclocked access can hang the SoC.
#
# BusyBox sh: no arrays, no [[ ]], no process substitution, no bash-isms.
# The cabinet has no RTC (date says 1970), so column 1 of the log is uptime in
# seconds.

FLAG=/userdata/host-mode
LOG=/userdata/hostmode.log
SETTLE=10        # seconds to let the system settle after S60 fires
ENUM_WAIT=45     # seconds to wait for a device on the port before falling back
NET_WAIT=30      # seconds to wait for a new network interface after enumeration

DRY=0; NOHUB=0
for a in "$@"; do
	case "$a" in
	  --dry-run) DRY=1 ;;
	  --no-hub)  NOHUB=1 ;;
	  *) echo "usage: $0 [--dry-run [--no-hub]]" >&2; exit 2 ;;
	esac
done
if [ "$NOHUB" = 1 ] && [ "$DRY" != 1 ]; then echo "--no-hub needs --dry-run" >&2; exit 2; fi
[ "$DRY" = 1 ] && LOG=/userdata/hostmode-dryrun.log

# Registers (docs/14). GRF_HOST sets iddig_en (bit 9) with iddig_output (bit 10)
# low: the controller sees an A-device connector and re-initialises as host.
# GRF_PIN clears the override so ID follows the connector pin again (B-device).
# The upper 16 bits are the GRF write-enable mask for bits 9 and 10.
GRF_CON0=0x2000817c      # GRF UOC0_CON0
GRF_STAT=0x2000814c      # GRF SOC_STATUS: bit 8 utmi_iddig, bit 5 bvalid
GOTGCTL=0x10180000       # dwc2: bit 16 ConIDSts (1 = B-device)
GUSBCFG=0x1018000c       # dwc2: read for the log only
GINTSTS=0x10180014       # dwc2: bit 0 CurMod (1 = host)
GRF_HOST=0x06000200
GRF_PIN=0x06000000
DWC2_DRV=/sys/bus/platform/drivers/dwc2
DWC2_DEV=10180000.usb
CFG_UDC=/sys/kernel/config/usb_gadget/rockchip/UDC

up() { cut -d' ' -f1 /proc/uptime; }
log() { printf '%s %s\n' "$(up)" "$*" >>"$LOG"; sync; }
snap() { printf -- '--- %s\n' "$1" >>"$LOG"; shift; "$@" >>"$LOG" 2>&1; sync; }
rd() { devmem "$1" 32; }
regs() {
	g=$(rd $GOTGCTL); u=$(rd $GUSBCFG); i=$(rd $GINTSTS); c=$(rd $GRF_CON0); s=$(rd $GRF_STAT)
	printf '  GOTGCTL=%s GUSBCFG=%s GINTSTS=%s GRF_CON0=%s GRF_STAT=%s | CurMod=%s ConIDSts=%s utmi_iddig=%s bvalid=%s\n' \
		"$g" "$u" "$i" "$c" "$s" $(( i & 1 )) $(( (g >> 16) & 1 )) $(( (s >> 8) & 1 )) $(( (s >> 5) & 1 ))
}
curmod() { i=$(rd $GINTSTS); echo $(( i & 1 )); }
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
wr() { printf '%s\n' "$1" >"$2"; }
# State-changing steps go through do_: logged and executed normally, logged only
# with --dry-run.
do_() {
	if [ "$DRY" = 1 ]; then log "DRY would run: $*"; return 0; fi
	log "run: $*"
	"$@" 2>>"$LOG"
}

# The dwc2 host controller's bus is the usbN directory under its platform device
# (usb1 here, because the other two root hubs take 2 and 3 at boot; usb1 is
# also the fallback if the directory is missing). Devices on that bus are
# N-<port>; N-0:1.0 is the root hub's own interface and does not count.
hcd_bus() {
	for b in "/sys/bus/platform/devices/$DWC2_DEV"/usb*; do
		[ -e "$b" ] && { basename "$b"; return 0; }
	done
	return 1
}
enumerated() {
	n=$(hcd_bus) || n=usb1
	n=${n#usb}
	for d in /sys/bus/usb/devices/"$n"-*; do
		[ -e "$d" ] || continue
		case "$d" in *:*) continue ;; esac
		return 0
	done
	return 1
}
new_ifaces() {
	for p in /sys/class/net/*; do
		n=$(basename "$p")
		case "$n" in lo|eth0|sit0) continue ;; esac
		echo "$n"
	done
}

bring_up_network() {
	# dhcpcd (started by S41dhcpcd in master mode) has not always picked up a
	# hot-plugged interface by itself; otg-host-force.sh asks it explicitly and
	# falls back to udhcpc. Same here.
	t=0
	while [ $t -lt $NET_WAIT ]; do
		[ -n "$(new_ifaces)" ] && break
		sleep 1; t=$((t + 1))
	done
	ifs=$(new_ifaces)
	if [ -z "$ifs" ]; then
		log "no new network interface within ${NET_WAIT}s (no Ethernet adapter on the dock?); host mode stays up without a network"
		return 0
	fi
	for ifn in $ifs; do
		log "interface $ifn present after ${t}s: bringing it up and asking for a lease"
		do_ ip link set "$ifn" up
		if [ "$DRY" = 1 ]; then
			log "DRY would run: dhcpcd -n $ifn  ||  udhcpc -i $ifn -b -q -t 5"
		else
			dhcpcd -n "$ifn" >>"$LOG" 2>&1 || udhcpc -i "$ifn" -b -q -t 5 >>"$LOG" 2>&1
		fi
	done
	sleep 10
	snap "net" sh -c 'ip addr show; ip route show'
}

restore_to_gadget() {
	# Verbatim sequence from tools/otg-restore.sh, minus its 90 s wait for a host.
	log "nothing enumerated within ${ENUM_WAIT}s: returning the port to the adb gadget (dwc2 reprobe)"
	for m in /media/usb*; do
		grep -q " $m " /proc/mounts || continue
		do_ umount "$m" || do_ umount -l "$m"
	done
	sync
	log "unbinding dwc2 platform driver"
	do_ wr "$DWC2_DEV" "$DWC2_DRV/unbind"
	sleep 1
	if [ "$DRY" != 1 ] && [ -e "$DWC2_DRV/$DWC2_DEV" ]; then
		log "unbind did not take; aborting before the GRF flip (port stays as it is)"
		exit 1
	fi
	log "dwc2 unbound (no dwc2 register reads until it is bound again)"
	do_ devmem $GRF_CON0 32 $GRF_PIN
	log "GRF iddig override cleared (ID back to pin)"
	sleep 2
	log "binding dwc2 platform driver"
	do_ wr "$DWC2_DEV" "$DWC2_DRV/bind"
	sleep 3
	if [ ! -e "$DWC2_DRV/$DWC2_DEV" ]; then
		log "dwc2 did NOT rebind: port is dead until a power-cycle; skipping register reads"
		snap "dmesg tail" sh -c 'dmesg | tail -n 20'
		exit 1
	fi
	log "dwc2 bound"
	snap "regs after reprobe" regs
	snap "gadget after reprobe" gadget
	# On this 4.19 kernel the configfs gadget re-attaches by itself when the UDC
	# returns, and an explicit write then fails with EBUSY. Only write if empty.
	if [ -z "$(cat $CFG_UDC 2>/dev/null)" ]; then
		log "UDC empty: attaching gadget"
		do_ wr "$DWC2_DEV" "$CFG_UDC" || { do_ wr "" "$CFG_UDC"; do_ wr "$DWC2_DEV" "$CFG_UDC"; }
		sleep 2
	else
		log "UDC already set ($(cat $CFG_UDC)): gadget re-attached on its own"
	fi
	ps | grep -q "[a]dbd" || { log "adbd not running; restarting"; do_ start-stop-daemon --start --quiet --background --exec /usr/bin/adbd; }
	snap "gadget final" gadget
	snap "dmesg tail" sh -c 'dmesg | tail -n 20'
	log "done: port is the adb gadget again; $FLAG is still present, so the next boot tries host mode again (rm it over adb for a plain boot)"
}

# ---------------------------------------------------------------------------
grep -q " /userdata " /proc/mounts || exit 1    # nowhere to log, and no flag could have been seen
if [ "$DRY" != 1 ] && [ -f "$LOG" ]; then mv -f "$LOG" "$LOG.1"; fi
: >"$LOG"
log "hostmode start  kernel $(uname -r)  dry-run=$DRY no-hub=$NOHUB  flag=$([ -e "$FLAG" ] && echo present || echo absent)  settle=${SETTLE}s enum-wait=${ENUM_WAIT}s"
sleep "$SETTLE"

# No dwc2 register read before this check: an unbound driver means gated clocks.
if [ ! -e "$DWC2_DRV/$DWC2_DEV" ]; then
	log "dwc2 is not bound to $DWC2_DEV; cannot switch, leaving the port alone"
	exit 1
fi
snap "regs at start" regs
snap "usb tree at start" usb_tree
snap "gadget at start" gadget
snap "dwc2 platform device children" ls "/sys/bus/platform/devices/$DWC2_DEV"

# sshd reads /root/.ssh/authorized_keys; /root is on the read-only squashfs, so
# the persistent copy on /userdata is bind-mounted over it every boot.
if grep -q " /root " /proc/mounts; then
	log "/root already bind-mounted"
elif [ -d /userdata/root ]; then
	do_ mount --bind /userdata/root /root
else
	log "/userdata/root missing: sshd runs, but no authorised key is available"
fi

# ---- mechanism A: GRF iddig override -> ID low -> A-device -> host ----------
if [ "$(curmod)" = "1" ]; then
	log "CurMod=1: controller is already in host mode; GRF write (devmem $GRF_CON0 32 $GRF_HOST) not needed"
else
	do_ devmem $GRF_CON0 32 $GRF_HOST
	n=0
	while [ $n -lt 6 ]; do
		[ "$(curmod)" = "1" ] && break
		sleep 1; n=$((n + 1))
	done
	if [ "$(curmod)" = "1" ]; then
		log "CurMod=1 after ${n}s: core is in host mode (GRF path)"
	elif [ "$DRY" = 1 ]; then
		log "DRY: CurMod still 0, as expected with nothing written"
	else
		# The host stack never started, so there is nothing to tear down: put the
		# override back and leave the gadget as it was.
		log "CurMod still 0 after ${n}s: override did not take; clearing it and leaving the gadget alone"
		do_ devmem $GRF_CON0 32 $GRF_PIN
		snap "regs" regs
		exit 1
	fi
fi
snap "regs after switch" regs

# ---- wait for something on the port -----------------------------------------
t=0; found=0
if [ "$NOHUB" = 1 ]; then
	log "DRY --no-hub: pretending nothing enumerates"
else
	while [ $t -lt $ENUM_WAIT ]; do
		if enumerated; then found=1; break; fi
		sleep 1; t=$((t + 1))
	done
fi

if [ "$found" = 1 ]; then
	log "device enumerated on the port after ${t}s (bus $(hcd_bus 2>/dev/null || echo usb1?))"
	sleep 3
	snap "usb tree" usb_tree
	bring_up_network
	snap "usb tree" usb_tree
	snap "storage" sh -c 'grep -E " sd[a-z]" /proc/partitions; grep -E "/media/|/dev/sd" /proc/mounts'
	snap "dmesg tail" sh -c 'dmesg | tail -n 20'
	log "host mode up; staying. To end it: rm $FLAG and power-cycle, or run otg-restore.sh over ssh"
	exit 0
fi

restore_to_gadget
exit 0
