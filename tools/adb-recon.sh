#!/bin/sh
# Phase 2: read-only reconnaissance over adb, once a shell is available.
#
# Writes NOTHING to the cabinet. Every command is a read. Run only after
# `adb devices` lists the cabinet.
#
#   sh adb-recon.sh > tmnt-recon.txt 2>&1
#
# This closes most of the project's open questions in one pass:
#   - is TMNT the same RK3128 platform as the Space Invaders image?
#   - which romset does it launch (tmnt or tmnt2)?
#   - total NAND size and free space on /userdata
#   - is the panel the same 800x480, and is it rotated?
#   - which input devices exist, and in what order (matters for the boot menu
#     and for RetroArch player assignment)
#   - why is adbd's gadget in the state it is?

A="adb shell"
run() { printf '\n########## %s\n' "$*"; $A "$@" 2>&1; }

echo "=== adb devices"; adb devices -l

run uname -a
run cat /proc/cmdline
run cat /proc/version
run cat /etc/os-release
run 'cat /proc/device-tree/model; echo'
run 'cat /proc/device-tree/compatible | tr "\0" " "; echo'

# --- storage: answers "how big is the NAND" and "how much room on userdata"
run cat /proc/partitions
run 'ls -l /dev/block/by-name/ 2>/dev/null || ls -l /dev/disk/by-partlabel/ 2>/dev/null'
run df -h
run mount

# --- memory / cpu
run free
run 'cat /proc/cpuinfo | head -30'
run 'cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null'

# --- what game does THIS cabinet run
run 'grep -n "^game=" /etc/init.d/S22startup.sh'
run 'ls -la /usr/share/libretro/*.zip'
run 'ls /usr/lib/libretro/'
run 'cat /etc/init.d/.usb_config'

# --- display: same panel? rotated?
run 'grep -E "video_rotation|screen_orientation|video_shader|aspect" /etc/retroarch.cfg'
run 'cat /userdata/.config/retroarch/retroarch.cfg 2>/dev/null | grep -E "rotation|orientation|menu_driver|shader" '
run 'cat /sys/class/graphics/fb0/virtual_size 2>/dev/null; cat /sys/class/graphics/fb0/modes 2>/dev/null'

# --- inputs: which devices, in which order (event0/event1 gate the boot menu)
run 'cat /proc/bus/input/devices'
run 'ls -l /dev/input/'

# --- userdata: what persists today
run 'ls -laR /userdata 2>/dev/null | head -60'

# --- why is the gadget in this state
run 'cat /sys/kernel/config/usb_gadget/rockchip/UDC 2>/dev/null; echo'
run 'cat /sys/class/android_usb/android0/state 2>/dev/null; echo'
run 'ls -l /sys/kernel/config/usb_gadget/rockchip/configs/b.1/ 2>/dev/null'
run 'ps | grep -iE "adbd|retroarch|uiconfig|audio_volume" | grep -v grep'
run 'ls -l /dev/usb-ffs/adb 2>/dev/null'

# --- running processes / boot log, for context
run 'dmesg | tail -40'

echo
echo "########## NOTE"
echo "Nothing above wrote to the cabinet. The natural next step is the backup:"
echo "  adb reboot loader     # deliberate, no button guessing"
echo "then rkdeveloptool on the host to read every partition before any change."
