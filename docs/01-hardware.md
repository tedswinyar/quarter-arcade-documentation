# Hardware

Verified on the TMNT cabinet itself over root adb (docs/09) unless marked
otherwise.

## SoC and board

**Rockchip RK3128** — quad Cortex-A7 @ 1.2 GHz, Mali-400 MP2, ARMv7 hardfloat,
**224 MB RAM**. Device-tree model on the running cabinet:

```
compatible = "rockchip,rk3128"
model      = "Rockchip RK3128 LBQ1293 board"
```

(The published Space Invaders *image* carries the generic "Fireprime"
reference-board DT in its resource blob; the running TMNT board identifies as
`LBQ1293` — the contract manufacturer's own board code, consistent with the
`LBQ1295A/B` codes in the SI firmware filenames.)

The u-boot stage carries a second, smaller DTB (`rockchip,rk3126-evb`); RK3126
is the same RK312x family. The kernel is monolithic — no `/lib/modules`.

Kernel cmdline (read from `/proc/cmdline`):

```
storagemedia=nand ... ro rootwait earlycon=uart8250,mmio32,0x20060000
console=ttyFIQ0 root=PARTUUID=614e0000-0000 rootfstype=squashfs
```

## Flash

**Samsung SLC NAND, 107.75 MiB** (220,672 × 512 B sectors), exposed through
Rockchip's FTL as `/dev/rkflash0`. Soldered; **no microSD, no eMMC** — there is
no boot-from-card escape hatch. `rkdeveloptool rfi`: block size 512 KB, page
2 KB.

Stock GPT (verified by dump; sectors of 512 B):

| Partition | Start | Size | Contents |
|---|---|---|---|
| (gap) | 0 | 8192 | GPT + reserved; backup GPT in the 33-sector tail at 220639 |
| `uboot` | 8192 | 8192 | u-boot + RK3126-EVB DTB (redundant copies) |
| `trust` | 16384 | 4096 | ARM Trusted Firmware (redundant copies) |
| `boot` | 20480 | 18432 | Android bootimg: kernel (7.85 MiB used) + resource |
| `rootfs` | 38912 | 165376 | squashfs 4.0/xz, read-only, 56.3 MiB used |
| `userdata` | 204288 | 16351 | ext2, read-write, mounted at `/userdata` |

The kernel mounts root by `PARTUUID=614e0000-0000` — a **prefix** of the
rootfs partition's GPT UUID. Any re-tabling must preserve the partition UUIDs.
(This cabinet's table has since been modified — rootfs shrunk, userdata grown;
see docs/13. The table above is the factory state, preserved in the dump.)

The read-only rootfs plus a writable `userdata` is the key structural fact for
modding: everything persistent that avoids reflashing lives in `/userdata`.

## Display

**1024×600 LVDS, unrotated** (`fb0`), driven behind a 4:3 bezel that hides
~115 px on the left and ~95 px on the right — the vendor renders the game in a
measured `custom_viewport` of 814×600 @ x=115. The SI image's DT describes a
different panel (800×480, rotated for the vertical game): **panels differ per
cabinet model**. A reviewer replaced a broken TMNT panel with a generic
AliExpress module (teardown: youtube.com/watch?v=Bc_gzM2Q2nk).

## Controls

Four identical player positions (blue/yellow/purple/red = Leo/Mikey/Donnie/
Raph), each a `Dashine Arcade 1293 Joystick` input device on a **serial-
attached MCU** (`serial0-0`) — not USB. Per position: stick (up/down/left/
right as key events; the MCU's left/right evdev codes are crossed — docs/10),
jump (`BTN_A`), attack (`BTN_B`), and one coin button (`BTN_PINKIE`, coin N →
player N). No start button — faithful to the 4-player original, coin = join.
Plus a volume-knob ABS device and an `adc-bootmode` ADC key.

## USB

- **Rear USB-C**: power input + the adb gadget (dwc2 OTG, peripheral only —
  no VBUS supply is wired, so it cannot host devices). Root adb shell from any
  Linux host; macOS cannot configure the gadget (docs/07).
- **Four front USB-A ports behind the coin doors**: designed for USB gamepads
  (vendor accessory; X360/8BitDo confirmed by reviewers on healthy units).
  **Dead on my unit** — no 5 V, no enumeration, a known repairable fault
  (docs/11).
- One EHCI/OHCI host port exists at the SoC with VBUS on; nothing has ever
  enumerated on it here.

## Physical (from the Numskull listing)

¼-scale replica of Konami's 1989 TMNT cabinet, wood; USB-C powered with an
internal rechargeable lithium battery; 3 W speaker with volume knob; light-up
marquee; 17.5″ × 9.2″ × 9.4″. Related: *Turtles in Time* variant and signed
Collector's Editions.

## Warranty

Rubber Road Ltd (Numskull's parent) gives a 1-year warranty that "shall not
apply … if the product has been modified, opened, altered". Opening the case
voids it. Everything documented in this repo was done **without opening the
case** — adb, loader and maskrom are all reachable over the rear USB-C.
