# Input map and the recovery ladder

Two reference facts established on the hardware without opening the case:
exactly what the control panel emits, and every rung of the path from a
normal boot down to maskrom and back.

## The input map

Each turtle position is a complete, identical player interface, one of the four
`Dashine Arcade 1293 Joystick` devices. Position order left to right matches
event order: blue = event0 (P1), yellow = event1 (P2), purple = event2 (P3),
red = event3 (P4). `tools/btnmap.py`, run on the cabinet, prints each press
labelled.

| Physical control | evdev code |
|---|---|
| stick up | `BTN_FORWARD` (277) |
| stick down | `BTN_BACK` (278) |
| stick left | `BTN_RIGHT` (273) † |
| stick right | `BTN_LEFT` (272) † |
| jump | `BTN_A` (304) |
| attack | `BTN_B` (305) |
| coin button N (left to right) | `BTN_PINKIE` (293) on event N−1 |

† Verified with held-stick tests: physical left emits `BTN_RIGHT`, physical
right emits `BTN_LEFT`. The MCU's codes are crossed and the vendor's autoconfig
profile (docs/11) compensates. Anything reading raw evdev (a custom picker, a
fork of the vendor's `uiconfig`) must apply the same swap.

There is no start button, faithful to the 4-player TMNT original where coin is
join; docs/11 describes how Start is provided for other games. The hidden boot
menu gate (`/opt/uiconfig/main.py`) checks `BTN_B` held on event0 and event1:
hold attack on blue and yellow at power-on. `adc-bootmode` (event5) is a
separate ADC key device; its button is unidentified and not needed.

The vendor's own boot menu shows the platform ships a working python3 + evdev
+ SDL2 + SDL_ttf stack, everything a custom game picker in the vendor's style
would need.

## The recovery ladder

```
normal boot ──adb reboot loader──▶ loader (PID 310c, "Loader")
loader ──rkdeveloptool rd 3──▶ maskrom (PID 310c, "Maskrom", bootROM answering)
maskrom ──rkdeveloptool db MiniLoaderAll.bin──▶ vendor loader running from RAM
any of the above ──rkdeveloptool rd──▶ normal boot (TMNT back, adb back)
```

- `rkdeveloptool db` is rejected in loader mode ("device does not support
  this operation"); it is a maskrom-only operation, and `rd 3` gets there from
  loader mode.
- The vendor `MiniLoaderAll.bin` (174 KB, `BOOT` magic) extracts from the SI
  RKFW image at header offsets `0x19` (loader offset) and `0x1D` (size). It is
  the only loader that can address this NAND; Rockchip's generic rkbin
  usbplug binaries download but fail every read and wedge the device until
  power-cycled (docs/07).
- `rfi` in loader mode: SAMSUNG SLC NAND, 107 MB / 220672 sectors, 512 KB
  erase block, 2 KB page.

### Loader reads are garbage past 32 MiB

`rkdeveloptool rl` returns `0xCC` filler instead of flash data for every LBA
at or above 65536 (device offset 32 MiB), reporting success. Below the line,
loader reads match the adb dump byte for byte (`gap-0`, `uboot`, `trust`,
`boot`); above it, pure `0xCC`. Chunked reads change nothing, and the SI
image's own loader has the same cap: a limitation of this loader generation,
not of the tool.

- Never trust an `rl` dump of `rootfs` or `userdata`. The adb block-device
  dump (`tools/adb-dump.sh`) is the only verified full-range read path.
- A loader-made "backup" of the whole flash is silently 70 % filler.
- `0xCC` tails are the tell. Check any loader read for them.

### Restore route by failure mode

| Cabinet state | Route |
|---|---|
| Linux boots, adb works | `adb` + `dd` the dumped images back (kernel block path; full range, read-verified) |
| Linux dead, u-boot alive | loader `wl` restores `uboot`, `trust`, `boot`, all below 32 MiB, i.e. everything needed to make Linux boot again; adb then handles the rest |
| u-boot dead too | a broken u-boot drops the bootROM into maskrom by itself; `db MiniLoaderAll.bin`, then `wl` |
| write above 32 MiB needed via loader | vendor-demonstrated (AndroidTool flashes the full RKFW image through this loader on SI cabinets), so `wl` past 32 MiB is expected to work even though `rl` does not; always verify by booting and hashing over adb |

Loader writes are verified on this hardware on the `trust` partition; the
recipes, with commands, are in docs/12. Newer rkbin components
(`rk312x_miniloader_slc_v2.65`, `rk3128_usbplug_slc_v2.65`) might lift the
read cap but need `boot_merger` (an x86 binary) to pack; not pursued.

## Front USB ports

The SoC exposes three USB host buses and usbmount is enabled with mountpoints
`/media/usb0` to `usb7` pre-created. On this unit the four front ports carry
no power and no data; the finding, the evidence and the repair pointer are in
docs/11.
