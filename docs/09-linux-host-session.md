# Linux host session: adb works, flash dumped, test romset booted

2026-09-02 evening. Cabinet connected by USB-C to a Linux host
(Ubuntu 24.04 noble, aarch64, kernel 6.17), driven over ssh
from the MBP. Three results, each one a milestone.

## Result 5 — macOS was the problem. adb just works on Linux

`lsusb -v` settled the macOS-era question (now summarised in docs/07): the descriptors are **fully
healthy**. One configuration (`iConfiguration "adb"`), one interface, class
`0xFF/0x42/0x01`, two bulk endpoints (EP2 OUT / EP1 IN, 512 B), gadget state
`CONFIGURED`, `adbd` running as root and bound to functionfs. The "half-alive
gadget / adbd unbound" theory from the macOS sessions was wrong — macOS simply refuses to
configure a gadget that Linux accepts without complaint.

Setup on the Linux host was nothing but `apt install adb`: Ubuntu's
`android-sdk-platform-tools-common` ships udev rules that already cover vendor
`0x2207`, so no root, no custom rules:

```
$ adb devices -l
<serial redacted>       device usb:3-1 product:occam model:Nexus_4 device:mako
```

(The Nexus 4 identity strings are leftovers in the vendor's adbd build.)
**`adb shell` is a root shell** — `uid=0(root)`, no authorization prompt.

Quirks: this adbd predates the `exec` service, so `adb exec-out` fails with
`error: closed`; binary dumps must be staged through the cabinet's tmpfs `/tmp`
and pulled (`tools/adb-dump.sh` does exactly this, verifying device-side vs
host-side sha256 for every file).

## Recon corrections and confirmations (full log: `local/recon/2026-09-02-adb-recon.txt`)

Same platform as the SI image: RK3128 quad A7 @ 1.2 GHz, 224 MB RAM, Linux
4.19.161 #140 (Jul 24 2023), Buildroot 2018.02-rc3, squashfs rootfs + ext2
userdata. DT model: **`Rockchip RK3128 LBQ1293 board`**. Game: `game=tmnt`,
`/usr/share/libretro/tmnt.zip` (1.8 MB), cores `mame2003` + `mame2003plus`.

Corrections to earlier docs:

- **The panel is 1024×600, not 800×480** (`fb0` virtual_size and mode both
  `1024x600`), unrotated (`video_rotation = 0`).
- **The control panel is not USB HID.** It is four `Dashine Arcade 1293
  Joystick` input devices on `serial0-0` (a serial-attached MCU on
  `/devices/platform/0.input`), plus a `Dashine Arcade Volume` ABS device and —
  notably — an **`adc-bootmode`** input device (`adc-keys`, event5). So an ADC
  boot-mode key *is* wired on this board after all; which physical button it is
  remains unidentified, and it no longer matters: `adb reboot loader` is
  available.
- The earlier "panel occupies player ports 1–4 as USB HID" framing was wrong in
  mechanism, right in effect: the four joystick devices still claim
  js0–js3/event0–event3, and event0/event1 still gate the hidden boot menu.

Also on board: sshd (`S50sshd`), dnsmasq, dhcpcd — a whole network stack with no
usable NIC (`eth0` exists but `Cannot attach to PHY`). Storage is `rkflash0`,
110,336 KiB (~107.75 MiB) with a GPT in the first 4 MiB gap:

| dev | name | sectors (512 B) | size |
|---|---|---|---|
| — | (GPT + parameter gap) | 0–8191 | 4 MiB |
| p1 | uboot | 8192 +8192 | 4 MiB |
| p2 | trust | 16384 +4096 | 2 MiB |
| p3 | boot | 20480 +18432 | 9 MiB (Android bootimg) |
| p4 | rootfs | 38912 +165376 | 80.75 MiB (squashfs 4.0/xz, **100% full**) |
| p5 | userdata | 204288 +16351 | 8 MiB ext2, **7.1 MiB free** |
| — | (tail gap) | 220639–220671 | 16.5 KiB |

## Result 6 — full stock firmware backup, no loader mode needed

`tools/adb-dump.sh` dumped every partition **and both unpartitioned gaps**
read-only over adb (staged via tmpfs, nothing written to flash), hash-verified
each transfer, and the archive now lives on both the Linux host
(`<backup-dir>/tmnt-stock/`) and a second machine (`local/firmware/tmnt-stock/`), with
`SHA256SUMS`.

Whole-device vs parts cross-check: uboot, trust, boot, rootfs and both gaps are
byte-stable across repeated reads. Only `userdata` drifts while the machine
runs — exactly 10 bytes of ext2 superblock/metadata bookkeeping near offset
37 KB, no file content. Treat `userdata.img` as a point-in-time snapshot;
its contents are re-creatable defaults anyway (S22startup.sh regenerates
`retroarch.cfg` from `/etc/retroarch.cfg` if missing).

This satisfies the project's gating decision ("nothing gets flashed until its
own firmware is dumped and archived") without ever leaving normal boot. Loader
mode is now only needed for *restore*, and `adb reboot loader` reaches it
deliberately whenever that day comes.

## Result 7 — additional content loads, RAM-only, fully reversible

The end-to-end mechanism, demonstrated with zero flash writes and verified
(2026-09-03) with *Gridlee* (Videa, 1982), which MAMEdev offers for free
non-commercial use under its stated terms (not included here), and which is in
this core's DAT:

1. `adb push gridlee.zip /tmp/` — the cabinet's tmpfs, RAM only
2. `killall retroarch`, then relaunch exactly as `S22startup.sh` does but with
   the new zip:

```sh
HOME=/userdata nohup retroarch \
    -c /userdata/.config/retroarch/retroarch.cfg \
    -L /usr/lib/libretro/mame2003plus_libretro.so \
    /tmp/gridlee.zip >/tmp/ra.log 2>&1 &
```

RetroArch came up clean (Mali GL initialised, no errors in the log). A power
cycle restores TMNT with no residue — `/tmp` is RAM.

Notes for the real mod: samples/artwork live under
`/usr/share/libretro/system/mame2003-plus/` in the read-only rootfs, so
sample-based games are silent-but-playable this way; persistent ROMs would go
in `userdata` (7.1 MiB free — many 0.78-era romsets fit) with a startup hook,
or into a rebuilt squashfs. That design decision is next.
