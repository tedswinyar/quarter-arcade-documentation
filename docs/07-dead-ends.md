# Dead ends — what we tried that didn't work, and why

Everything here failed, wasted time, or turned out to rest on a wrong
assumption. It is kept **only** so the next person doesn't repeat it. The
working methods live in docs/09–13.

## macOS cannot talk to the adb gadget. Use Linux.

Symptoms on macOS (26.x, Apple Silicon): the cabinet enumerates as `2207:0006`
with correct strings, but `ioreg` shows the node `!registered, !matched`, adb
fails all interfaces with `kIOReturnNoResources`, and libusb doesn't see the
device at all (its darwin backend only lists registered services). Hours were
spent theorizing the cabinet's `adbd` wasn't bound to functionfs. **The gadget
was healthy the whole time** — on Ubuntu, `apt install adb` and it just works,
root shell, no udev fiddling (the stock Android udev rules cover vendor
`0x2207`). Lesson: an unconfigurable gadget on macOS says nothing about the
device; test on Linux before theorizing.

macOS-side gotchas recorded along the way:

- `system_profiler SPUSBDataType` is empty on macOS 26 — the data type is now
  `SPUSBHostDataType`.
- `ADB_TRACE=usb adb devices` traces only the client; to see enumeration you
  must trace the server: `ADB_TRACE=usb adb server nodaemon`.
- The pip `libusb` package is x86_64-only; use Homebrew's.
- `rkdeveloptool` does build fine on macOS/arm64 with a stub `config.h` and
  Homebrew libusb — no autotools needed. (It was ultimately run from Linux.)

## Don't reason about ports from the static device tree

The kernel DTB in the firmware image marks `usb2-phy/otg-port` **disabled**,
which led to a confident (written-down) prediction that the adb gadget could
never enumerate. Wrong: u-boot fixes up the DT at boot. The same trap exists
for the MMC controllers and `/memory`. Lesson: on Rockchip, the static DT
records the reference design, not the running board — statuses are only
conclusive when read from `/proc/device-tree` on the live system.

## Coin-button loader-mode entry: wrong generation

The 2019 Pac-Man updater's "hold Coin2 while connecting USB" was carried over
to this 2023 RK3128 cabinet. Coin buttons 1, 2 and 1+2 at power-on: nothing.
The generations share nothing here — the 2019 units were micro-USB with a
bespoke updater; the 2023 units use Rockchip's standard tooling. An ADC
boot-mode key **does** exist on the board (`adc-bootmode`, event5), but which
physical button it is was never identified, and it stopped mattering entirely:
with adb, `adb reboot loader` enters loader mode deliberately, and
`rkdeveloptool rd 3` goes from loader to maskrom (docs/10).

For the record, loader/maskrom on this board is PID `0x310c` on vendor
`0x2207`; the gadget PID table (from the vendor's own `usbdevice` script) maps
`adb`→`0x0006`, `ums`→`0x0000`, `mtp`→`0x0001`, `acm`→`0x1005`.

## USB keyboard in a front port + F1: doubly doomed

The original plan — keyboard in a front port, F1 opens RetroArch's menu —
failed for a reason that took days to isolate: **the front USB ports on this
unit carry no power and no data in any state** (two sticks × four ports, two
keyboards, rear cable in and out, kernel watched throughout: zero events, no
5 V, ever). The ports are real on healthy units — Numskull sells a gamepad for
them and reviewers confirm X360/8BitDo pads work — so this is a **per-unit
hardware fault**, apparently common enough that a repair video exists
("How to Fix a TMNT Quarter Arcade Machine", youtube.com/watch?v=Wtde-IpX-Zs).

Even with working ports the F1 plan was shakier than it looked: several
standard menu UI labels are absent from the shipped RetroArch binary (it's a
trimmed build), and no arcade-encoder autoconfig profile binds a menu button.
What actually works is binding the menu toggle in the persistent
`retroarch.cfg` (docs/11) — no keyboard involved.

Diagnostic worth keeping: a keyboard's Caps Lock LED is a **host detector** —
it only toggles if a USB host enumerated the keyboard and sent the set-LED
command. No LED at all = no 5 V = don't bother debugging software.

## Loader reads return filler past 32 MiB — and only the vendor loader works at all

`rkdeveloptool rl` against this cabinet's loader **silently returns `0xCC`
filler for every sector past LBA 65536 (32 MiB)** while reporting success. A
"full dump" via loader is 70% garbage. Verified byte-for-byte against adb
reads below the line; pure `0xCC` above it. Chunking doesn't help; the SI
image's own loader (uploaded via maskrom `db`) has the same cap.

Attempting to fix it with Rockchip's public rkbin components made it worse:
both `rk3128_usbplug_v2.63` and `rk3128_usbplug_slc_v2.65` (packed with
`rkdeveloptool pack`, which needs a one-line off-by-one patch to work at all)
download fine and then **fail every read, even LBA 0, and wedge the device
until power-cycled**. The vendor's own `MiniLoaderAll` is the only loader that
can address this NAND. Consequences and recipes: docs/12.

## Ozone menu: invisible edges behind the bezel

Enabling RetroArch's ozone menu produced a UI cut off on both sides. Not a
resolution bug: the cabinet's 4:3 bezel physically hides ~115 px left / ~95 px
right of the 1024×600 panel, and the vendor renders the game inside a measured
`custom_viewport` (814×600 @ x=115). Ozone/XMB always paint the full panel;
**RGUI renders through the game viewport** and fits exactly. Use RGUI.

## Small quirks that cost real time

- This adbd predates the `exec` service: `adb exec-out` fails with
  `error: closed`. Stage binary dumps through the cabinet's tmpfs `/tmp` and
  `adb pull` them (`tools/adb-dump.sh`).
- The Dashine panel MCU emits **crossed left/right evdev codes** (physical
  left = `BTN_RIGHT`). The vendor's autoconfig profile compensates; anything
  reading raw evdev must too (docs/10).
- `rkdeveloptool rd` from a wedged usbplug fails ("Reset Device failed!") —
  that state is RAM-only; power-cycle and carry on.
- RetroArch has `config_save_on_exit = true`: edit `retroarch.cfg` only after
  `killall -9 retroarch`, or a clean exit overwrites your edit.
