# Restore path proven (with one landmine), and the full input map

2026-09-02, later the same evening as docs/09. Cabinet on the Linux host over USB-C.

## The input map (captured live with `tools/btnmap.py`)

Each turtle position is a complete, identical player interface — one of the four
`Dashine Arcade 1293 Joystick` devices. Position order left-to-right matches
event order: blue=event0 (P1), yellow=event1 (P2), purple=event2 (P3),
red=event3 (P4).

| Physical control | evdev code |
|---|---|
| stick up | `BTN_FORWARD` (277) |
| stick down | `BTN_BACK` (278) |
| stick left | `BTN_RIGHT` (273) † |
| stick right | `BTN_LEFT` (272) † |
| jump | `BTN_A` (304) |
| attack | `BTN_B` (305) |
| coin button N (left→right) | `BTN_PINKIE` (293) on event N−1 |

† **Confirmed** by a dedicated held-motion test (3-second holds, one stick,
nothing else): physical left emits `BTN_RIGHT`, physical right emits
`BTN_LEFT`. The MCU's codes are crossed and the vendor's autoconfig profile
(docs/11) compensates. Anything reading raw evdev (a custom picker, the
`uiconfig` fork) must apply the same swap.

There is no start button — faithful to the 4-player TMNT original, where
coin = join. The hidden boot menu gate (`/opt/uiconfig/main.py`) checks
`BTN_B` held on event0 **and** event1: hold **attack on blue and yellow** at
power-on. `adc-bootmode` (event5) is a separate ADC key device; untriggered
during the capture, so still unidentified — and now irrelevant.

The vendor's own boot menu proves the platform ships working **python3 +
evdev + SDL2 + SDL_ttf** — everything needed for a custom game-picker in the
vendor's own style.

## Restore path: every rung of the ladder verified

Round trip exercised end-to-end, no case opening, no button guessing:

```
normal boot ──adb reboot loader──▶ loader (PID 310c, "Loader")
loader ──rkdeveloptool rd 3──▶ maskrom (PID 310c, "Maskrom", bootROM answering)
maskrom ──rkdeveloptool db MiniLoaderAll.bin──▶ vendor loader running from RAM
any of the above ──rkdeveloptool rd── ▶ normal boot (TMNT back, adb back)
```

- `rkdeveloptool db` is **rejected in loader mode** ("device does not support
  this operation") — maskrom only. `rd 3` gets there from loader mode.
- The vendor `MiniLoaderAll.bin` (174 KB, `BOOT` magic) extracts from the SI
  RKFW image at header offsets `0x19` (loader offset) / `0x1D` (size).
- `rfi` in loader mode: **SAMSUNG SLC NAND, 107 MB / 220672 sectors, 512 KB
  erase block, 2 KB page** — closes the "total NAND size" question for good.

### ⚠️ The landmine: loader reads are garbage past 32 MiB

`rkdeveloptool rl` returns **`0xCC` filler instead of flash data for every LBA
≥ 65536 (device offset ≥ 32 MiB)**. No error is reported — the dump "succeeds".
Verified: below 32 MiB, loader reads match the adb dump byte-for-byte (`gap-0`,
`uboot`, `trust`, `boot` all identical); past it, 100% `0xCC` (71 MB of filler
checked). Chunked reads change nothing. The SI image's own loader, downloaded
via `db`, has the **same cap** — it is a firmware limitation of this loader
generation (2023, v2.6x-era), not a tool bug.

Consequences:

- **Never trust an `rl` dump of `rootfs` or `userdata`** on this machine. The
  adb block-device dump (`tools/adb-dump.sh`) is the only verified full-range
  read path.
- A loader-made "backup" of the whole flash would silently be 70% filler — the
  exact trap this note exists to prevent.
- `0xCC` tails are the tell. Check any loader read for them.

### Restore strategy by failure mode

| Cabinet state | Restore route |
|---|---|
| Linux boots, adb works | `adb` + `dd` the dumped images back (kernel block path; full range, read-verified) |
| Linux dead, u-boot alive | `adb reboot` unavailable; loader `wl` restores `uboot`/`trust`/`boot` — **all below 32 MiB**, i.e. everything needed to make Linux boot again, after which adb handles the rest |
| u-boot dead too | maskrom (`rd 3` won't be available — but a broken u-boot drops to maskrom by itself) → `db MiniLoaderAll.bin` → `wl` |
| write >32 MiB needed via loader | vendor-demonstrated: AndroidTool flashes the full 77 MB RKFW image through this same loader on SI cabinets, so `wl` past 32 MiB is expected to work even though `rl` does not — **always verify by booting and re-hashing over adb** |

Untested (deliberately): actual `wl` writes. First write test, when needed,
should be byte-identical data to `trust` (2 MB, < 32 MiB, redundant copies
internally, verified backup on two machines).

Possible upgrade: `rockchip-linux/rkbin` publishes newer components
(`rk312x_miniloader_slc_v2.65`, `rk3128_usbplug_slc_v2.65`) that might fix the
deep-read cap, but packing them needs `boot_merger` (x86 binary in rkbin;
would need building from u-boot source for arm64/macOS). Parked — not needed
for the current plan.

## Front USB ports

The SoC exposes three USB host buses on the cabinet, usbmount is enabled
(`/media/usb0`–`7`, vfat/exfat/ntfs/ext), mountpoints pre-created. Whether the
front-panel ports are wired to those buses is still unverified — no stick has
been inserted yet. If they are, ROM storage becomes effectively unlimited with
zero flash writes.
