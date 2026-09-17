# USB host mode on the rear USB-C: working, reversible, and exclusive with adb

The rear USB-C port can act as a USB host. Verified on my TMNT unit on
2026-09-14 with a self-powered USB-C dock: the dock's hubs, its gigabit
Ethernet adapter and two flash drives all enumerated on the cabinet, and the
stock `usbmount` auto-mounted a FAT partition at `/media/usb0`. This
supersedes the "peripheral only, cannot host" statements in docs/01, 06 and
11, which were true of the port as shipped but not of the hardware.

Status at the bottom. The switch is reversible and the work so far has not
touched the flash; everything below is RAM state that a power-cycle undoes.

## Why the port behaves as peripheral-only

Three facts from the firmware image and the live system:

| | |
|---|---|
| Controller | `usb@10180000`, `snps,dwc2`, `dr_mode = otg`; kernel has `CONFIG_USB_DWC2_DUAL_ROLE=y`, `USB_STORAGE`, `BLK_DEV_SD`, `VFAT_FS` |
| Core | Synopsys DWC OTG **2.91a** (`GSNPSID 0x4F54291A`); `GHWCFG2` OtgMode = 0, i.e. HNP/SRP-capable dual-role silicon |
| PHY | `usb2-phy@17c/otg-port` is **`disabled` in the live device tree** (`/proc/device-tree`), not just in the static DTB. u-boot fixes up the dwc2 node but leaves the phy's OTG port off |

So the driver stack is dual-role, but two inputs are missing: the cabinet
supplies no VBUS (it is a power sink on that connector), and with the phy's
OTG port disabled the Rockchip `inno-usb2` OTG state machine never runs, which
is why `extcon` reads `USB=0 USB-HOST=0 USB_VBUS_EN=0` in every state
(docs/11). The controller is left permanently seeing "B-device" and runs the
adb gadget.

A self-powered dock removes the first gap: it brings its own 5 V. The second
gap can be closed from software.

## Mechanism: override the ID signal in the GRF

The phy driver's `otg_mode` sysfs attribute exists on this unit but rejects
every write with "No support otg" because the OTG port is disabled (docs/07).
What it would have written is two bits in the GRF, and those can be written
directly with `devmem`:

| Register | Address | Bits | Meaning |
|---|---|---|---|
| GRF `UOC0_CON0` | `0x2000817c` | 9 `iddig_en`, 10 `iddig_output` | override the ID input the controller sees. Upper 16 bits are write-enables |
| GRF `SOC_STATUS` | `0x2000814c` | 8 `utmi_iddig`, 5 `bvalid` | read-back of the ID and VBUS-valid signals |
| dwc2 `GINTSTS` | `0x10180014` | 0 `CurMod` | 0 device, 1 host |
| dwc2 `GOTGCTL` | `0x10180000` | 16 `ConIDSts` | 1 B-device, 0 A-device |
| dwc2 `GUSBCFG` | `0x1018000c` | 29 `ForceHostMode` | fallback, not needed |

```sh
devmem 0x2000817c 32 0x06000200    # ID low  -> A-device -> host
devmem 0x2000817c 32 0x06000000    # ID back to the pin -> B-device -> gadget
```

Within a second of the first write `CurMod` reads 1 and `ConIDSts` 0, the
driver takes the connector-ID-change interrupt, re-initialises as host and the
root hub `usb1` starts enumerating whatever is on the connector. USB 2.0 data
does not depend on Type-C CC negotiation, so a dock whose upstream port
expects a laptop still works on the data pair. Bit-position provenance: the
`rk312x` port config in Rockchip's `phy-rockchip-inno-usb2.c`, corroborated on
the live unit by the status bits at `0x14c` and the two detect-status bits
already set at `0x17c` before any write.

## What enumerated

Dock: a USB-C laptop dock powered from its own PD input, upstream cable into
the cabinet. Second run, 2026-09-14:

| Path | Device | Result |
|---|---|---|
| 1-1 | VIA Labs `2109:2817` USB 2.0 hub | enumerated |
| 1-1.1 | VIA `2109:0102` billboard | enumerated |
| 1-1.2 | Realtek `0bda:5411` 4-port hub | enumerated |
| 1-1.2.1 | Realtek `0bda:8153` gigabit Ethernet | enumerated; `r8152` is built in |
| 1-1.2.2 | PNY 126 GB flash drive | `sdc`, one partition, not FAT, not mounted |
| 1-1.2.4 | SanDisk Cruzer 62 GB | `sdd`, `sdd1` vfat **auto-mounted at `/media/usb0`** |
| 1-1.4 | Genesys `05e3:0749` card reader | enumerated, no media |

`usbmount` is the stock one (`/media/usb0`..`usb7`, vfat/exfat/ntfs/ext,
`FS_MOUNTOPTIONS` empty). Nothing had to be configured on the cabinet for the
mount to happen.

## Procedure

While the port is in host mode the adb link does not exist, because the adb
gadget and the host controller are the same port. Until networking works
(below) every experiment is therefore a timed, detached script:

```sh
adb push tools/otg-host-force.sh /userdata/otg-host-force.sh
adb shell '(setsid sh /userdata/otg-host-force.sh 90 240 </dev/null >/dev/null 2>&1 &)'
#   within 90 s: unplug the Linux host, plug the powered dock in
#   host mode is held 240 s and sampled every 5 s
#   then the port is restored; plug the host back in and
adb pull /userdata/otg-host-force.log
```

Three launch details that cost time: `adb shell 'setsid nohup … &'` does not
survive the adb session ending; the subshell form above does. But when that
subshell is the *only* command in the adb session, the script sometimes never
starts (twice out of three tries here); following it with `sleep 2; ps` in the
same session has worked every time. Check the first line of the log before
swapping cables. And the cabinet's BusyBox `ip` has no `-br`.

Do not unplug the dock while the port is in host mode (see status). Let the
script restore first.

## Networking, which ends the adb conflict

Working on my unit as of 2026-09-15. The pieces were all in the stock image:
`r8152` driver built in, `sshd` running with `PermitRootLogin yes`, `dhcpcd`
running in master mode, `/sbin/ip` and `udhcpc` available. With an Ethernet
cable in the dock, the adapter comes up as `eth1`, gets a carrier within a few
seconds of enumeration, and the boot-time `dhcpcd` takes a lease on it by
itself (the earlier run where nothing appeared was the under-powered dock, not
DHCP). The lease request carries the hostname `rk3128`.

`/root` is on the read-only squashfs, so an authorised key has to live in
`/userdata/root/.ssh/authorized_keys` (mode 600) with
`mount --bind /userdata/root /root` done each boot; the script does that now,
and sshd reads the key file at authentication time, so no restart is needed.
Root ssh in with that key works while the port is a host. Finding the cabinet
on the LAN: sweep for port 22 and match the ed25519 host key in
`/etc/ssh/ssh_host_ed25519_key.pub` (its comment is `lzy@fedora`, a leftover
from whoever built the image), or look for the dock adapter's MAC. It does not
announce itself over mDNS.

Once ssh is up, `touch /userdata/keep-host` and the script exits without
restoring the port, leaving the cabinet a networked USB host until the next
power-cycle. Everything below that point was done live over ssh.

## Loading content from the drive

A FAT drive in the dock auto-mounts at `/media/usb0` and a romset copied there
shows up in RGUI's file browser. On my unit the core picker that follows was
empty, so nothing could be launched from the drive. Cause: RetroArch 1.9.7
matches content to cores through core info files, and this image ships none.
`libretro_directory` and `libretro_info_path` both point at
`~/.config/retroarch/cores` (RetroArch's `HOME` is `/userdata`), which exists
and is empty; the one core is `/usr/lib/libretro/mame2003plus_libretro.so`.
Symlinking the core into that directory was not enough on its own, and with
`core_info_cache_enable = "true"` a restart writes a `core_info.cache` that
records the core with no info and locks the empty picker in.

What worked, all under `/userdata` so it survives boots and needs no config
edit:

1. Symlink the core into `~/.config/retroarch/cores/`.
2. Put `mame2003plus_libretro.info` beside it
   (`tools/retroarch/mame2003plus_libretro.info`; the one line that matters is
   `supported_extensions = "zip"`).
3. Delete `core_info.cache` and restart RetroArch. The stock
   `S22startup.sh` has `start` and `stop` but no `restart`, so: `kill -9` the
   pid in `/var/run/retroarch.pid`, then relaunch with the same command line
   the script uses (`HOME=/userdata retroarch -c … -L … tmnt.zip`, detached).

After that, Load Content on a zip from the drive starts it straight away with
no picker, which is RetroArch's behaviour when exactly one core claims the
extension. A playlist is friendlier still: `tools/retroarch/Arcade (USB).lpl`
in `~/.config/retroarch/playlists/` lists the drive's romsets with the core
already bound, and shows up in RGUI's main menu. Verified on the hardware with
*Gridlee* from `/media/usb0/roms/`.

## Status (2026-09-15)

Established:

- Host mode is reachable from software with the GRF override, on the stock
  kernel, without flashing anything. Five runs, five clean switches.
- A self-powered dock enumerates fully and a FAT drive auto-mounts within
  seconds of the swap.
- Ethernet through the dock works: DHCP lease from the stock `dhcpcd`, root
  ssh in with a key. The adb link is no longer the only way in.

Open, in the order they need solving:

1. **Switching back wedges the gadget after a real host session.** With
   nothing attached during host mode the gadget returns cleanly. After the dock
   had been enumerated, the return left the gadget `DISCONNECTED` and it never
   re-enumerated (the host saw a device that would not answer descriptor
   reads); a power-cycle fixed it. Run 4 added a configfs UDC unbind/rebind on
   the way back and that made no difference: the gadget reported bound, the
   host still got no descriptors. The residual state is in the controller, not
   the gadget layer. The script now unbinds and rebinds the `dwc2` platform
   driver itself around the ID flip, with the drives unmounted first, so the
   controller is probed from scratch. Not yet validated. With ssh available
   the switch-back matters less: a power-cycle restores adb anyway, and most
   work can be done over the network instead.
2. **Unplugging a device in host mode appears to hang the host stack.** In the
   third run the script's sampling stopped at the moment the dock was pulled,
   the game kept running, the restore never ran and the gadget never came
   back. One occurrence; treat as a hypothesis, but do not hot-unplug until it
   is understood.
3. **Dock power matters.** On a different wall supply the inner 4-port hub
   enumerated and reported no connections: the Ethernet adapter and the drive
   were absent even though the drive's LED was lit. The same dock on the
   original charger enumerated everything. Likely the dock disables its
   downstream ports without a PD contract; untested.
4. **Persistence.** Nothing on the read-only rootfs executes anything from
   `/userdata` at boot, so host mode is a per-boot command until either an
   init script is added to the rootfs (docs/13 already ships a custom slim
   rootfs, so this is in reach) or the phy's `otg-port` is enabled in the
   device tree so the stock `otg_mode` attribute works.
5. **Slow small writes to a flash drive on this path.** Formatting a 64 GB
   stick as FAT32 on the cabinet ran at tens of kilobytes per second, and
   BusyBox `fdisk` takes sector numbers in cylinders unless given `-u`.
   Partition and format drives on a PC; the cabinet only needs to read them.

Run logs are kept locally (`local/recon/2026-09-1?-otg-host-*.log`) and are
not published; they contain device serials and MAC addresses.
