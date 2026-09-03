# Platform capabilities

Kernel/DT facts below were extracted from the published SI image (same
platform build) and, where it matters, verified on the running TMNT cabinet.
The kernel carries its own build config (`CONFIG_IKCONFIG`); reproduce with:

```bash
IMG=local/firmware/SI-LBQ1295A-2023-12-22-5dB-Version3.img
python3 tools/rkfw_probe.py summary $IMG
python3 tools/rkfw_probe.py kconfig $IMG local/kernel.config
python3 tools/rkfw_probe.py dts     $IMG 'usb|dwmmc|panel|opp|eth|hdmi'
```

## Kernel

Rockchip vendor 4.19 BSP, ARMv7 32-bit. The TMNT ships `4.19.161 #140`
(2023-07-24, verified via `uname`); the SI image carries `#142` (2023-12-12) —
same tree, different build. `CONFIG_MODULES=y` but nothing shipped; extra
drivers mean building against Rockchip's public 4.19 tree.

## Clocks and silicon (verified: CPU max 1.2 GHz, 224 MB RAM)

| | |
|---|---|
| CPU | 4× Cortex-A7, OPP up to **1200 MHz** |
| GPU | Mali-400 MP2, OPP up to **480 MHz**, OpenGL ES 2.0 |
| DDR | OPP up to **456 MHz**; 224 MB usable RAM |
| Video decode | `hevc`, `iep`, `rga` all **disabled** — no hardware decode/2D-blit |
| HDMI | **disabled** (unrouted on this board) |

## Display

Panels differ per cabinet model. TMNT (verified live): **1024×600 LVDS,
unrotated**, game drawn in a bezel-matched 814×600 viewport (docs/01). The SI
image's DT: 800×480, rotated for the vertical game. Both are low-resolution —
good news for emulation headroom.

## Storage (verified)

**Samsung SLC NAND, 107.75 MiB**, via Rockchip's FTL as `rkflash0`.
Consequences:

- **No microSD boot** — no run-mods-off-a-card escape hatch.
- `userdata` is the only writable internal space (grown to 47.7 MiB, docs/13);
  keep write-heavy things off it.
- Root is squashfs, mounted read-only by GPT `PARTUUID`.

Don't trust the static DT on storage (or USB): the image's DT disables all
MMC controllers *and* the NAND controller — u-boot fixes nodes up at boot.
The live system is the only authority (docs/07).

## USB (verified on the TMNT)

| Port | Reality |
|---|---|
| Rear USB-C | dwc2 OTG in **peripheral-only** operation: the adb gadget (root shell from Linux hosts). No VBUS supply wired → cannot host devices, even with an OTG adapter, without external power tricks |
| 4 front USB-A | designed for gamepads (vendor accessory; confirmed working by reviewers on healthy units) — **dead on my unit**, no 5 V (docs/11) |
| SoC EHCI/OHCI host port | up, VBUS on, nothing attached/enumerated here |

Gadget functions compiled in: configfs with ACM, mass-storage, MTP,
functionfs (adb — the one enabled). **No RNDIS/ECM** → no USB network
tethering to a host.

## Networking

None usable — no PHY populated, no Wi-Fi hardware or firmware. sshd/dnsmasq/
dhcpcd all start anyway (BSP leftovers). Compiled in for a USB dongle:
`ax88179_178a`, `r8152`, `cdc_ether`/`ncm`/`mbim`, `smsc75xx/95xx`, `dm9601`
and friends; Wi-Fi only `rt2800usb`. (Front-port fault currently makes this
moot on my unit.)

## Other kernel features worth knowing

- Filesystems `=y`: `ext4`, `squashfs`, `overlayfs`, `vfat`, `fuse`, `nfs`,
  `nfsd`; FUSE helpers for exFAT/NTFS in the rootfs.
- Net/container plumbing `=y`: `bridge`, `tun`, `veth`, netfilter/NAT,
  cgroups, namespaces, `zram`, swap.
- USB host `=y`: `usb_storage`, `usb_hid`, `usb_serial`, `usb_acm`,
  `snd_usb_audio` — everything a working host port would need.

## Roughly what class of machine is this?

**Raspberry Pi 2 Model B silicon clocked ~33% higher; in practice about a Pi
Zero 2 W.**

| | This cabinet (RK3128) | Pi 2 B | Pi Zero 2 W | Pi 3 B |
|---|---|---|---|---|
| CPU | 4× A7 @ 1.2 GHz | 4× A7 @ 0.9 GHz | 4× A53 @ 1.0 GHz | 4× A53 @ 1.2 GHz |
| RAM | 224 MB | 1 GB | 512 MB | 1 GB |
| Storage | soldered NAND, 108 MB | microSD | microSD | microSD |
| Network | none | 100M Eth | Wi-Fi | Eth + Wi-Fi |
| Display | LVDS panel only | HDMI | mini HDMI | HDMI |

Emulation ceiling at this resolution, by analogy with a Pi 2 on the same
cores: MAME 0.78-era comfortably (the shipped core), NES/SNES/Mega Drive/GB/
PC Engine trivially, CPS1/CPS2/Neo Geo via FBNeo fine, PS1 probably playable.
N64/Saturn/Dreamcast: no. Note the 224 MB RAM is tighter than any Pi —
RetroArch + mame2003-plus fits, heavyweight cores may not.

The compute is not the interesting asset — the cabinet is.
