# Working with the cabinet over adb from a Linux host

The rear USB-C port runs an adb gadget with `adbd` as root and no
authorisation, and a Linux host talks to it with nothing but the distribution's
adb package. macOS cannot configure the gadget at all (docs/07); use Linux, in
a VM if need be.

## Setup

`apt install adb` is the whole setup on Ubuntu: the platform-tools package
ships udev rules that already cover Rockchip's vendor id `0x2207`, so no root
and no custom rules.

```
$ adb devices -l
<serial>       device usb:3-1 product:occam model:Nexus_4 device:mako
```

The Nexus 4 identity strings are leftovers in the vendor's adbd build.
`adb shell` lands in a root shell (`uid=0`), no prompt.

The gadget's descriptors are healthy: one configuration (`iConfiguration
"adb"`), one interface of class `0xFF/0x42/0x01`, two 512-byte bulk endpoints,
gadget state `CONFIGURED`. If a host fails to talk to it, suspect the host.

## Quirks

- This adbd predates the `exec` service, so `adb exec-out` fails with
  `error: closed`. Stage binary output through the cabinet's tmpfs `/tmp` and
  `adb pull` it; `tools/adb-dump.sh` does exactly that and checks a sha256 on
  both sides for every file.
- The adb server on the host sometimes needs `adb kill-server` after the
  cabinet re-enumerates (power-cycle or a return from USB host mode) before the
  device shows.
- Detached scripts that must outlive the adb session need the subshell form
  described in docs/14.

## What the cabinet reports

Platform: RK3128 quad Cortex-A7 at 1.2 GHz, 224 MB RAM, Linux 4.19.161
(Buildroot 2018.02-rc3), squashfs rootfs plus ext2 `userdata`. Device-tree
model `Rockchip RK3128 LBQ1293 board`. The startup script's `game=tmnt` points
at `/usr/share/libretro/tmnt.zip` (1.8 MB); cores `mame2003` and
`mame2003plus` are present.

- Panel: `fb0` is 1024×600, unrotated (`video_rotation = 0`).
- Controls: not USB HID. Four `Dashine Arcade 1293 Joystick` input devices on
  `serial0-0` (a serial-attached MCU at `/devices/platform/0.input`), a
  `Dashine Arcade Volume` ABS device, and an `adc-bootmode` ADC key device
  (`adc-keys`, event5) whose physical button is unidentified and unneeded,
  since `adb reboot loader` reaches loader mode on demand. The four joystick
  devices are js0–js3 / event0–event3, and event0/event1 gate the hidden boot
  menu (docs/03). Full input map in docs/10.
- Network: sshd, dnsmasq and dhcpcd all start with no usable NIC (`eth0`
  exists but `Cannot attach to PHY`). A USB Ethernet adapter in host mode
  changes that (docs/14).
- Storage: `rkflash0`, 110,336 KiB, GPT in the first 4 MiB gap. Stock table
  (the current table differs; docs/13):

| dev | name | sectors (512 B) | size |
|---|---|---|---|
| — | (GPT + parameter gap) | 0–8191 | 4 MiB |
| p1 | uboot | 8192 +8192 | 4 MiB |
| p2 | trust | 16384 +4096 | 2 MiB |
| p3 | boot | 20480 +18432 | 9 MiB (Android bootimg) |
| p4 | rootfs | 38912 +165376 | 80.75 MiB (squashfs 4.0/xz, 100 % full) |
| p5 | userdata | 204288 +16351 | 8 MiB ext2, 7.1 MiB free |
| — | (tail gap) | 220639–220671 | 16.5 KiB |

`tools/adb-recon.sh` collects all of the above read-only.

## Full flash backup, read-only, from normal boot

`tools/adb-dump.sh` dumps every partition and both unpartitioned gaps over adb,
staged through tmpfs, writing nothing to flash, with a sha256 check on each
transfer. Keep the result in two places with its `SHA256SUMS`. It is the only
trusted full-range read path on this hardware: loader-mode reads return filler
past 32 MiB (docs/10, docs/12).

Everything except `userdata` is byte-stable across repeated reads. `userdata`
drifts by about ten bytes of ext2 superblock bookkeeping while the machine
runs, no file content; treat `userdata.img` as a point-in-time snapshot whose
contents are re-creatable defaults anyway (`S22startup.sh` regenerates
`retroarch.cfg` from `/etc/retroarch.cfg` when it is missing).

Take this backup before changing anything. Loader mode is then needed only for
restore, and `adb reboot loader` reaches it deliberately.

## Zero-risk content test, RAM only

The quickest proof that a romset works on the core, with no flash writes and
no residue after a power-cycle:

```sh
adb push <set>.zip /tmp/              # tmpfs, RAM only
adb shell 'killall retroarch; HOME=/userdata nohup retroarch \
    -c /userdata/.config/retroarch/retroarch.cfg \
    -L /usr/lib/libretro/mame2003plus_libretro.so \
    /tmp/<set>.zip >/tmp/ra.log 2>&1 &'
```

That is the vendor's own launch line with a different content path. *Gridlee*
(Videa, 1982; offered by MAMEdev for free non-commercial use under its stated
terms, not included here) is in this core's DAT and makes a good test set.
Sample-based games are silent this way because samples live in the read-only
rootfs; docs/11 has the persistent, menu-driven version of content loading and
the samples path.
