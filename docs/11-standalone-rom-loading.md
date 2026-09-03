# Standalone ROM loading: working, zero-flash, fully reversible

2026-09-02, end of the Linux-host evening (docs/09, docs/10). The goal of the
project — load additional MAME romsets, keep the cabinet restorable — is now
**functionally achieved** without touching the read-only rootfs. Everything
lives in `userdata` (the partition designed to be written) and reverses with
two file deletions.

## How it works

Hold **coin 1** (leftmost coin button) and press **blue attack** → RetroArch
menu (RGUI) → Load Content → pick a zip from `/userdata/roms/` → the game runs
on the mame2003-plus core. Power cycle always returns to TMNT (the launch
command in the read-only `S22startup.sh` is untouched).

Menu controls: stick navigates, **attack = confirm, jump = back**. Verified on
the hardware: coins still register normally (5-frame hotkey block delay), the
combo opens the menu, and a test romset loads and plays (*Gridlee* — Videa,
1982, offered by MAMEdev for free non-commercial use under its stated terms;
not included here).

## The persistent changes (all in `/userdata/.config/retroarch/retroarch.cfg`)

| key | stock | now | why |
|---|---|---|---|
| `input_enable_hotkey_btn` | `nul` | `4` | coin = hotkey-enable (hold) |
| `input_menu_toggle_btn` | `nul` | `6` | attack = menu toggle (with hotkey held) |
| `rgui_browser_directory` | `default` | `/userdata/roms` | browser opens in the ROM folder |
| `menu_driver` | `ozone` | `rgui` | see bezel note below |
| `menu_linear_filter` | `false` | `true` | RGUI readability |
| `menu_show_quit_retroarch` | `true` | `false` | quitting RA would strand a black screen until power cycle |
| `menu_show_shutdown` / `menu_show_reboot` | `true` | `false` | cabinet users use the power switch |

Plus: `/userdata/roms/` created (first tenant: `gridlee.zip`, 25 KB, the
MAMEdev free-use test romset), and a byte-exact stock copy of the config saved
on-device as
`retroarch.cfg.stock`.

**Editing discipline:** `config_save_on_exit = "true"`, so RetroArch rewrites
the cfg from memory when it exits cleanly. Always `killall -9 retroarch`
*before* editing the file, then reboot; otherwise a clean exit clobbers edits.

## Button indices: the vendor's own autoconfig profile

`/usr/share/libretro/autoconfig/udev/Dashine_Arcade_Joystick.cfg` binds each
panel position (vendor/product `2e2c:1293`):

| udev btn | evdev code | physical | RetroPad |
|---|---|---|---|
| 0 | `BTN_LEFT` (272) | stick **right** | Right |
| 1 | `BTN_RIGHT` (273) | stick **left** | Left |
| 2 | `BTN_FORWARD` (277) | stick up | Up |
| 3 | `BTN_BACK` (278) | stick down | Down |
| 4 | `BTN_PINKIE` (293) | coin | Select |
| 5 | `BTN_A` (304) | jump | B |
| 6 | `BTN_B` (305) | attack | A |

The left/right evdev-name crossing observed in docs/10 is real — the vendor
compensates for it in this profile. No Start button exists anywhere.

## The bezel discovery: why ozone was unusable

The panel is 1024×600 but the cabinet's 4:3 bezel physically hides ~115 px on
the left and ~95 px on the right. The vendor renders the game inside
`custom_viewport 814×600 @ x=115` (`aspect_ratio_index = 23`, custom) to fit
the opening. Ozone/XMB always paint the full panel, so their edges vanish
behind plastic; **RGUI renders through the same viewport pipeline as game
content** and fits the visible window exactly. Confirmed visually: green RGUI
border fully on-glass with gray margin beyond it.

## Front USB ports: functional by design — faulty on my unit

The measurements and the verdict evolved in opposite directions; both are
recorded because the measurements stay valid.

**What my unit does** (tested exhaustively):

1. All four ports × two sticks (one known good): zero kernel events, USB
   topology never leaves the three bare root hubs.
2. Two keyboards, all ports: **no LEDs ever** → no 5 V at any port.
3. Rear-cable-unplugged test with a detached on-cabinet logger (224 samples):
   no role switch, no enumeration, extcon stuck at
   `USB=0 USB-HOST=0 USB_VBUS_EN=0` in every state — the OTG ID/VBUS detect
   isn't wired, so there is no hidden host mode on the USB-C either.
4. SoC side: EHCI host port up, `vcc_host_5v` on (GPIO116 out-hi).

**What the design does** (web research, 2026-09-02):

- Numskull's spec for the TMNT cabinets: *"4x front USB ports (hidden behind
  the coin doors) allow the use of USB gaming controllers (sold separately)."*
  The Quarter Arcades USB Controller accessory is "designed for the TMNT
  range". No firmware caveats anywhere.
- Reviewers confirm on real units: wired Xbox 360 and 8BitDo SN30 pads work;
  PS5/Switch Pro pads don't. **Player assignment is by plug-in order, not
  port** (first pad is always Leonardo).
- A repair video exists: "How to Fix a TMNT Quarter Arcade Machine"
  (youtube.com/watch?v=Wtde-IpX-Zs) — "a simple fix on the controller ports".
  Port failure is a known, user-fixable fault on this model.

**Verdict: per-unit hardware fault** — the front-port assembly (hub board or
its harness, behind the coin doors) is disconnected or dead. This also
re-explains the dead-keyboard result of 2026-09-01: no power, so input
plumbing was never the issue. Two candidate architectures, undecided:

- ports → internal hub → EHCI (the waiting host port; `vcc_host_5v` may be
  its intended rail), or
- ports → Dashine panel MCU as a limited USB host bridging pads onto its
  serial joystick channels — which would explain plug-order assignment and
  the picky pad compatibility more naturally.

Diagnosis path if repaired/reseated (coin-door access, no case opening): a
device appearing on the EHCI bus ⇒ hub theory; input events with no USB
enumeration ⇒ MCU theory.

**Until repaired: ROM storage is `/userdata` (7.1 MB free).** A USB-C OTG
adapter on the back port could host mass storage in principle, but sacrifices
adb while in use — parked.

## Adding / removing ROMs

Only load romsets you own or are otherwise entitled to (docs/04 has the
project's line on this). Romsets must be **MAME 0.78-era** (mame2003-plus),
not current MAME — wrong-
version romsets are the single most common failure mode. The authoritative
compatibility list ships on the cabinet itself:
`/usr/share/libretro/system/mame2003-plus/mame2003-plus.xml` — 5,010 entries
(2,836 parents + 2,174 clones) with the exact ROM names and CRCs the core
expects. Pull it once (`adb pull`) and check candidates against it rather than
guessing. Classics are tiny — 30–200 KB each; TMNT itself is 1.8 MB.

```sh
adb push <romset>.zip /userdata/roms/     # add
adb shell rm /userdata/roms/<romset>.zip  # remove
```

Sample-based games (e.g. original Space Invaders sounds) look for samples
under the read-only `/usr/share/libretro/system/mame2003-plus/samples/` — such
games run silent unless the system dir is overridden; note
`system_directory` in the cfg points into userdata
(`~/.config/retroarch/system`), so samples zips can go to
`/userdata/.config/retroarch/system/mame2003-plus/samples/`.

## Restore to factory

```sh
adb shell "killall -9 retroarch
cp /userdata/.config/retroarch/retroarch.cfg.stock /userdata/.config/retroarch/retroarch.cfg
rm -rf /userdata/roms
sync"
adb reboot
```

(Or simply delete the cfg — `S22startup.sh` regenerates it from
`/etc/retroarch.cfg` at next boot. And `local/firmware/tmnt-stock/userdata.img`
can always be written back wholesale.)
