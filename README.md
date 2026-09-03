# quarter-arcade-documentation

Preservation and interoperability documentation for the **Numskull "Quarter
Arcades"** ¼-scale arcade cabinets — what the hardware actually is, what the
stock firmware runs, how to back it up and restore it, and how to work with it
without opening the case or relying on the vendor. The work is grounded in a
TMNT cabinet but most of it applies across the RK3128-based range.

## Why this exists

These machines are licensed collectibles with no public technical
documentation, no published recovery image for most models, and soldered
storage — so an owner who wants to keep one working, diagnose a fault, or
recover from a bad state currently has nothing to go on. This repository is an
attempt to fill that gap: understand the platform, establish a safe backup and
restore path, and document it so the knowledge outlives any one cabinet.

## Findings at a glance

| | |
|---|---|
| SoC | **Rockchip RK3128** (quad Cortex-A7 @ 1.2 GHz, Mali-400 MP2), board `LBQ1293`, 224 MB RAM |
| OS | Buildroot 2018.02 Linux 4.19.161, BusyBox init, monolithic kernel |
| Emulator | **RetroArch 1.9.7** + `mame2003plus_libretro.so` (MAME 0.78-era romsets); `mame2003` also present |
| Game ROM | `/usr/share/libretro/tmnt.zip` — a normal MAME romset zip in the read-only rootfs |
| Storage | Samsung SLC NAND, **107.75 MiB** (`rkflash0`), soldered, no microSD. Read-only squashfs rootfs + writable ext2 `userdata` |
| Debug access | **root adb shell over USB-C from a Linux host** (macOS cannot configure the gadget); serial `ttyFIQ0` root console exists but needs the case opened |
| Recovery | loader and maskrom both reachable over USB-C (`adb reboot loader`, `rkdeveloptool`); loader reads return filler past 32 MiB — see docs/12 |
| Panel | **1024×600** LVDS, unrotated; game drawn in a custom 814×600 viewport matching the 4:3 bezel opening |
| Controls | 4× serial-MCU joystick devices ("Dashine Arcade 1293"), one per player, each with jump/attack/coin; **not** USB HID |
| Front USB | 4 ports behind the coin doors, designed for USB gamepads (confirmed working on other units); **dead on my unit** — a known, repairable fault |
| Hidden menu | hold **attack on the first two player positions at power-on** → MAME cheats, CRT filter toggle |
| Networking | none usable — `sshd`/dnsmasq/dhcpcd all start, but there is no PHY and no wifi |
| Class of machine | ≈ Raspberry Pi 2 silicon; MAME 0.78 comfortably, 16-bit consoles trivially, nothing N64-class |

## Layout

```
docs/01..06                  hardware, firmware format, software stack, routes, sources, platform
docs/07-dead-ends.md         approaches that did not work, and why
docs/09-linux-host-session.md  root adb, recon, full flash dump, content-loading proof
docs/10-restore-path-and-inputs.md  recovery ladder, 32 MiB loader-read limit, input map
docs/11-standalone-rom-loading.md   content loading, config keys, front-USB findings
docs/12-restore-runbook.md          recovery recipes, each mechanism exercised on the hardware
docs/13-storage-expansion.md        repartition + slim rootfs: userdata 8 → 47.7 MiB
tools/unsquash_rkfw.py       stdlib-only squashfs reader for RKFW images
tools/rkfw_probe.py          kernel / config / device-tree extraction from an RKFW image
tools/adb-dump.sh            full read-only flash backup over adb (tmpfs-staged, hash-verified)
tools/adb-recon.sh           read-only recon over adb
tools/btnmap.py              labelled evdev event logger (runs on the cabinet)
tools/linux-probe.sh         first-contact USB probe for a Linux host
tools/usbwatch.sh            USB identity watcher (macOS-era, historical)
data/                        derived facts: rootfs path listing (no file contents)
```

## Contents and scope

This repository contains only original documentation and tools. **It includes
no firmware images, no ROM data, no extracted vendor-file contents, no
artwork, no manuals, and no vendor source.** Product names, trademarks, short
attributed quotations, links, and factual metadata remain the property of
their respective owners. The docs describe the platform and record file hashes
so findings can be independently reproduced from an owner's own cabinet; they
do not reproduce vendor software. Any romsets you load must be ones you own or
are otherwise entitled to use.

Every technical claim in docs/01–06 is either verified on the running cabinet
or explicitly attributed to Numskull's own published Space Invaders firmware
image (the same platform build) where that is the source. docs/09–13 are the
working session logs behind the results.

## Status of the research

- **Backup and restore** — a complete flash backup is taken read-only over adb
  (docs/09), the recovery ladder through loader and maskrom is exercised
  end-to-end, and the restore path is written up with a real write verified on
  the hardware (docs/12). The one sharp edge is that loader reads return filler
  past 32 MiB, so adb is the only trusted full-range read path.
- **Hardware faults** — my unit's four front USB ports carry no power and
  enumerate nothing; the ports are a genuine feature on healthy units, so this
  is a per-unit fault (docs/11).
- **Content loading** — additional MAME 0.78-era romsets load through the stock
  RetroArch via a persistent config change and an on-panel menu combo, with no
  changes to boot firmware and full reversibility (docs/11).
- **Storage** — the rootfs partition was slimmed and `userdata` grown from 8 to
  47.7 MiB, entirely over adb with pre-commit hash verification (docs/13).

## Open questions

*Updated as more information comes in.*

- I've not been able to identify a published TMNT firmware image, so for now
  the only recovery baseline is an owner's own dump.
- Whether the front-port fault on my unit is a loose internal connector or a
  failed sub-board (not yet opened for inspection).
- Official corresponding-source locations for the firmware's GPL-licensed
  components (kernel / BusyBox / RetroArch) have not yet been identified;
  availability remains unverified.
