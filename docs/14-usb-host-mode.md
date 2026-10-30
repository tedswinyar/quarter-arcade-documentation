# USB host mode on the rear USB-C: working, reversible, and exclusive with adb

The rear USB-C port, which ships as an adb gadget only, can act as a USB host.
With a self-powered USB-C dock on it the cabinet enumerates hubs, a gigabit
Ethernet adapter and flash drives, the stock `usbmount` auto-mounts a FAT
partition at `/media/usb0`, the stock `dhcpcd` takes a lease, and root ssh
works. That supersedes the "peripheral only, cannot host" statements in
docs/01, 06 and 11, which were true of the port as shipped but not of the
hardware.

The switch is done from software at run time and touches nothing on the
flash; a power-cycle undoes it, and a tested restore path returns the port to
adb without one. Host mode and adb are exclusive, because the gadget and the
host controller are the same port.

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

## What you need

- **A self-powered USB-C dock on a supply it can negotiate a proper PD
  contract with.** The cabinet provides no power on the port. This is the
  single most important item: see the first pitfall below.
- **A USB Ethernet adapter the stock kernel drives.** Realtek `r8152`/`r8153`
  is built in and is what has been used; nothing needs loading.
- **A FAT-formatted drive, partitioned and formatted on a PC.** The cabinet
  reads it fine; writing to it from the cabinet is very slow (see pitfalls).
- **A Linux host with adb for the first switch each boot.** macOS cannot drive
  the adb gadget (docs/07). Once ssh is up the Linux host is not needed.

What enumerates, by class, on a typical laptop dock: the dock's USB 2.0 hubs,
a USB-C billboard device, the Ethernet adapter (`eth1`), USB mass storage
(`sdX`, FAT partitions auto-mounted at `/media/usb0`, `/media/usb1`, …) and a
card reader. `usbmount` is the stock one (vfat/exfat/ntfs/ext,
`FS_MOUNTOPTIONS` empty); nothing has to be configured for the mount.

## Procedure

`tools/otg-host-force.sh` does the switch as a timed, detached script, because
adb disappears the moment the port becomes a host:

```sh
adb push tools/otg-host-force.sh /userdata/otg-host-force.sh
adb shell '(setsid sh /userdata/otg-host-force.sh 120 600 </dev/null >/dev/null 2>&1 &); sleep 2; ps | grep [o]tg-host'
#   within 120 s: unplug the Linux host, plug the powered dock in
#   host mode is held 600 s and sampled every 5 s; the dock enumerates,
#   eth1 gets a lease, and you ssh in (next section)
#   touch /userdata/keep-host over ssh to stay in host mode indefinitely;
#   otherwise the script restores the port to adb at the end of the window
```

Pick the delay to suit how long the cable swap takes; the window only has to
be long enough to ssh in and create `keep-host`. The script also bind-mounts
`/userdata/root` on `/root` so sshd finds the authorised key, and brings up
any new interface with `dhcpcd` (falling back to `udhcpc`).

Launch details that cost time: `adb shell 'setsid nohup … &'` does not survive
the adb session ending; the subshell form above does. When that subshell is
the *only* command in the adb session the script sometimes never starts;
following it with `sleep 2; ps` in the same session has worked every time.
Check the first line of `/userdata/otg-host-force.log` before swapping
cables. The cabinet's BusyBox `ip` has no `-br`.

## Networking and ssh

The pieces are all in the stock image: `r8152` driver built in, `sshd`
running with `PermitRootLogin yes`, `dhcpcd` running in master mode, `/sbin/ip`
and `udhcpc` available. With an Ethernet cable in the dock the adapter comes
up as `eth1`, gets a carrier within a few seconds of enumeration, and `dhcpcd`
takes a lease by itself. The lease request carries the hostname `rk3128`.

`/root` is on the read-only squashfs, so an authorised key has to live in
`/userdata/root/.ssh/authorized_keys` (mode 600) with
`mount --bind /userdata/root /root` done each boot; the script does that, and
sshd reads the key file at authentication time, so no restart is needed.

Finding the cabinet on the LAN: if the gateway's resolver learns DHCP
hostnames, `dig +short rk3128` (or `rk3128.localdomain`) answers; it does not
always. Otherwise match the ed25519 host key in
`/etc/ssh/ssh_host_ed25519_key.pub` (its comment is a user@host string left by
whoever built the image) or look for the Ethernet adapter's MAC in the
gateway's client list. It does not announce itself over mDNS. Make one ssh
attempt about 90 s after the switch rather than polling: gateways with
intrusion protection can block a host that probes port 22 repeatedly, for
minutes at a time, and the cabinet then looks down while it is up.

Once in, `touch /userdata/keep-host`. The script consumes the flag at the end
of its window and exits without restoring the port, leaving the cabinet a
networked USB host until the next power-cycle or an explicit restore. Bulk
transfers over this path are fine on a properly powered dock (a 20 MB file in
a few seconds).

## Returning to adb without a power-cycle

Simply clearing the GRF override after a host session leaves the gadget bound
but dead: `DISCONNECTED`, never re-enumerating, the host seeing a device that
answers no descriptor reads. Rebinding the configfs UDC does not help; the
residual state is in the controller. What works, validated after a full dock
session: unmount the drives, unbind the `dwc2` platform driver
(`/sys/bus/platform/drivers/dwc2/unbind`) while still in host mode so the HCD
tears down in order, clear the override, bind the driver again so a fresh
probe sees a B-device and starts the gadget. On this kernel the configfs
gadget re-attaches itself when the UDC reappears, so the explicit UDC write
reports `EBUSY`; that is harmless. No dwc2 register reads between unbind and
bind: the driver gates the clocks on remove and an unclocked access can hang
the SoC.

`otg-host-force.sh` does this at the end of its window when `keep-host` is
absent. `tools/otg-restore.sh` is the same sequence as a standalone step for
ending a `keep-host` session over ssh; it refuses to run unless the port is in
host mode and dwc2 is bound, and it kills the ssh session by design. Plug the
Linux host back in afterwards; the restart of the adb server on that host
(`adb kill-server`) is sometimes needed before the device shows.

## Loading content from the drive

A FAT drive in the dock auto-mounts at `/media/usb0` and a romset copied there
shows up in RGUI's file browser. The core picker that follows is empty on the
stock image, so nothing can be launched from the drive. Cause: RetroArch 1.9.7
matches content to cores through core info files, and this image ships none.
`libretro_directory` and `libretro_info_path` both point at
`~/.config/retroarch/cores` (RetroArch's `HOME` is `/userdata`), which exists
and is empty; the one core is `/usr/lib/libretro/mame2003plus_libretro.so`.
Symlinking the core into that directory is not enough on its own, and with
`core_info_cache_enable = "true"` a restart writes a `core_info.cache` that
records the core with no info and locks the empty picker in.

What works, all under `/userdata` so it survives boots and needs no config
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
already bound and shows up in RGUI's main menu;
`tools/retroarch/make-playlist.py` generates it from the drive's `roms/`
folder. Verified with *Gridlee* from `/media/usb0/roms/`. Controls, Start
buttons and vertical-game viewports for content other than TMNT are in
docs/11.

## Pitfalls

- **An under-powered dock supply is the failure to suspect first.** On a weak
  USB-C adapter the dock's inner hub either reports no downstream devices at
  all (drive LED lit, nothing enumerated) or, worse, enumerates and then flaps:
  the Ethernet adapter logs `r8152 ... Rx status -71` (USB protocol errors),
  the inner hub disconnects and re-enumerates every 2 to 20 seconds, and after
  a few minutes the whole dock drops with `dwc2 ... Not connected` while the
  game keeps running. The same dock, cable, drive and Ethernet on a 60 W
  adapter ran with zero disconnects and zero protocol errors. Disabling USB
  autosuspend changes nothing. Treat `Rx status -71` as a power symptom.
- **Do not hot-unplug the dock while the port is a host.** In one session the
  stack hung the moment the dock was pulled: sampling stopped, the restore
  never ran, the gadget never came back. One occurrence, so treat it as a
  hypothesis, but let the restore run first.
- **Prepare drives on a PC.** Small writes to a flash drive through this path
  run at tens of kilobytes per second; formatting a 64 GB stick on the cabinet
  took about fifteen minutes. BusyBox `fdisk` also takes sector numbers in
  cylinders unless given `-u`. The cabinet only needs to read the drive.
- **Capture the whole kernel log when diagnosing.** The script's
  `dmesg | tail -15` samples lose the first event of a failure. A loop that
  dumps `dmesg` to `/userdata/dmesg-live.txt` whenever its hash changes, and a
  gateway-ping log alongside it, survive a power-cycle and showed the real
  shape of the power problem above.
- **Probe once, not in a loop** (see Networking and ssh).
- **Case-only renames on the FAT drive are silently ignored** from the
  cabinet (`mv PacMan.zip pacman.zip` leaves the entry as it was, and a
  case-insensitive `ls` then confirms the wrong name). Rename through a
  temporary name and check with a case-sensitive match.

## Open: persistence

Nothing on the read-only rootfs executes anything from `/userdata` at boot, so
host mode is a per-boot command until an init script is added to the rootfs
(docs/13 already ships a custom slim rootfs, so this is in reach) or the phy's
`otg-port` is enabled in the device tree so the stock `otg_mode` attribute
works. The pieces are in place: the cabinet boots normally with the dock
already attached, the restore path above gives a boot-time script a safe
fall-back to adb when no hub is present, and a flag file on `/userdata` makes
it reversible without reflashing.

Run logs are kept locally and are not published; they contain device serials
and MAC addresses.
