#!/bin/sh
# Phase 1: what does a Linux host make of the cabinet's USB gadget?
#
# Run on a Linux box with the cabinet connected by USB-C. Read-only; touches
# nothing on the cabinet. Answers the question macOS could not: does the ADB
# interface (class 0xFF, subclass 0x42, protocol 0x01) actually exist?
#
#   sh linux-probe.sh
#
# Interpreting the result:
#   * an interface 0xFF/0x42/0x01 with 2 bulk endpoints -> descriptors are fine,
#     macOS was the problem, and adb should work here
#   * bNumInterfaces 0, or the config descriptor missing/short -> adbd really is
#     unbound on the cabinet, and loader mode is the only way in
#   * "Product ID" other than 0006 -> already in loader/maskrom mode: stop and
#     use rkdeveloptool instead

SUDO=""
[ "$(id -u)" != "0" ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

echo "=========== 1. is it on the bus?"
lsusb -d 2207: || echo "  no 0x2207 device seen by lsusb"

echo
echo "=========== 2. full descriptors (the decisive part)"
$SUDO lsusb -v -d 2207: 2>/dev/null | sed -n '1,120p'

echo
echo "=========== 3. sysfs view"
for d in /sys/bus/usb/devices/*; do
    [ -r "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor" 2>/dev/null)" = "2207" ] || continue
    echo "  $d"
    for f in idVendor idProduct bNumConfigurations bNumInterfaces bMaxPower \
             bDeviceClass speed serial product manufacturer version; do
        [ -r "$d/$f" ] && echo "    $f = $(cat "$d/$f" 2>/dev/null)"
    done
    echo "    interfaces:"
    for i in "$d":*; do
        [ -r "$i/bInterfaceClass" ] || continue
        echo "      $(basename "$i")  class=$(cat "$i/bInterfaceClass") \
sub=$(cat "$i/bInterfaceSubClass") proto=$(cat "$i/bInterfaceProtocol") \
eps=$(cat "$i/bNumEndpoints" 2>/dev/null) driver=$(basename "$(readlink "$i/driver" 2>/dev/null)" 2>/dev/null)"
    done
done

echo
echo "=========== 4. kernel log (enumeration errors show up here)"
$SUDO dmesg 2>/dev/null | grep -iE "usb|rockchip|rk3xxx" | tail -25

echo
echo "=========== 5. adb"
if command -v adb >/dev/null 2>&1; then
    adb kill-server >/dev/null 2>&1
    $SUDO adb devices -l 2>&1        # root avoids needing a udev rule
else
    echo "  adb not installed. On Debian/Ubuntu: sudo apt install -y android-tools-adb"
    echo "  On Fedora: sudo dnf install -y android-tools"
fi

echo
echo "=========== done"
echo "If an 0xFF/0x42/0x01 interface is listed above, adb should work — if 'adb"
echo "devices' still shows nothing, it is a permissions problem: run it as root,"
echo "or add:  SUBSYSTEM==\"usb\", ATTR{idVendor}==\"2207\", MODE=\"0666\""
echo "to /etc/udev/rules.d/51-rockchip.rules and re-plug."
