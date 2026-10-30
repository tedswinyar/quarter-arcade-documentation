# Standalone ROM loading: zero-flash, fully reversible

Additional MAME romsets load through the stock RetroArch without touching the
read-only rootfs. Everything lives in `userdata` (the partition designed to be
written) and reverses with a few file deletions.

## How it works

Hold **coin 1** (leftmost coin button) and press **blue attack** → RetroArch
menu (RGUI) → Load Content → pick a zip from `/userdata/roms/` → the game runs
on the mame2003-plus core. Power cycle always returns to TMNT (the launch
command in the read-only `S22startup.sh` is untouched).

Menu controls: stick navigates, **attack = confirm, jump = back**. Coins still
register normally (5-frame hotkey block delay). *Gridlee* (Videa, 1982; offered
by MAMEdev for free non-commercial use under its stated terms, not included
here) is in the core's DAT and makes a good test set.

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
| `input_remapping_directory` | `/usr/share/libretro/config/remaps` | `~/.config/retroarch/config/remaps` | remaps on the writable partition (see "Starts and buttons" below) |
| `rgui_config_directory` | `/usr/share/libretro/config` | `~/.config/retroarch/config` | per-game overrides on the writable partition (see "Vertical games" below) |

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

## Front USB ports: functional by design, faulty on my unit

**What my unit does:**

1. All four ports × two sticks (one known good): zero kernel events, USB
   topology never leaves the three bare root hubs.
2. Two keyboards, all ports: **no LEDs ever** → no 5 V at any port.
3. Rear-cable-unplugged test with a detached on-cabinet logger (224 samples):
   no role switch, no enumeration, extcon stuck at
   `USB=0 USB-HOST=0 USB_VBUS_EN=0` in every state — the OTG ID/VBUS detect
   isn't wired, so there is no hidden host mode on the USB-C either.
4. SoC side: EHCI host port up, `vcc_host_5v` on (GPIO116 out-hi).

**What the design does:**

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
explains why a keyboard in a front port never did anything: no power, so
input plumbing was never the issue. Two candidate architectures, undecided:

- ports → internal hub → EHCI (the waiting host port; `vcc_host_5v` may be
  its intended rail), or
- ports → Dashine panel MCU as a limited USB host bridging pads onto its
  serial joystick channels — which would explain plug-order assignment and
  the picky pad compatibility more naturally.

Diagnosis path if repaired/reseated (coin-door access, no case opening): a
device appearing on the EHCI bus ⇒ hub theory; input events with no USB
enumeration ⇒ MCU theory.

**Until repaired: ROM storage is `/userdata`** (grown to 47.7 MiB by
docs/13). The rear USB-C can host mass storage from a self-powered dock (a FAT
drive auto-mounts at `/media/usb0`), at the cost of the adb link while in host
mode; mechanism, procedure and pitfalls in docs/14.

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

`tools/datcheck.py` does that check: point it at the pulled DAT (default
`local/cabinet-dat/mame2003-plus.xml`) and one or more zips, and it reports
each expected ROM as present, wrong CRC, or missing, follows `merge=` into a
sibling parent zip for split clone sets, flags BIOS sets and optional samples,
and exits non-zero unless every zip is fully loadable. `--info <set>` prints
what the DAT expects for a set name. `tools/retroarch/make-playlist.py` then
builds the `Arcade (USB).lpl` playlist from the drive's `roms/` folder with
titles from the same DAT, so the menu lists everything on the drive with the
core already bound. Both need nothing beyond the Python standard library and
never touch the cabinet. The playlist checked into `tools/retroarch/` is the
one-entry Gridlee example; a real one describes a particular drive and stays
on the cabinet.

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

## Starts and buttons for games that are not TMNT

The cabinet has no start button: on TMNT coin is join. Every other game needs
Start, and each stick only reaches two of MAME's buttons, so the two-player
layout is rebuilt with RetroArch remaps. The vendor's remap directory is on the
read-only rootfs; the cfg now points at `~/.config/retroarch/config/remaps`
(`HOME` is `/userdata`), and `tools/retroarch/remaps/MAME 2003-Plus/` holds
the files, copied there verbatim.

Two mechanisms, both plain RetroArch 1.9.7 features. `input_remap_port_pN`
("Mapped Port") sends user N's input to a chosen libretro port, and several
users may share one port. Per-user button remaps rebind or disable (`-1`)
individual RetroPad inputs. Hotkeys (the menu combo) read raw button indices
and are unaffected.

`MAME 2003-Plus.rmp`, the core remap, applies to every game that has no
remap of its own:

| Stick | Role |
|---|---|
| blue (user 1) | player 1: stick, attack = button 1, jump = button 2, coin |
| yellow (user 2) | coin = 1P Start; attack = P1 button 3, jump = P1 button 4; stick off |
| purple (user 3) | coin = 2P Start; attack = P2 button 3, jump = P2 button 4; stick off |
| red (user 4) | player 2: stick, attack = button 1, jump = button 2, coin |

The attack/jump swap is deliberate. The vendor profile binds jump to RetroPad B
and attack to RetroPad A; the core reads B as MAME button 1 and A as button 2;
TMNT's driver has jump on button 1, so TMNT came out right and nearly every
other game (button 1 = attack by convention) came out reversed. The core
remap swaps them; `tmnt.rmp` keeps the vendor layout. RetroPad Y is button 3
and X is button 4, confirmed on a three-button game.

Four-player games need all four sticks live, so each gets its own game
remap: copy `four-player.rmp.example` to `<setname>.rmp` in the same folder
(it is the four-stick layout with the attack/jump swap applied); `tmnt.rmp` is
the stock mapping. RetroArch looks for `<core>/<content basename>.rmp` first,
then the core file.

Remaps load when content loads, so a change takes effect on the next game
started from the menu; only the cfg edit needed a RetroArch restart. What
this cannot fix: six-button fighters and the
dial, trackball and rotary games, which play but badly.

**Editing discipline for the cfg still applies** (kill -9 first). The copy
taken before this change is `retroarch.cfg.2026-10-28` beside the live file.

## Vertical games and the bezel

The panel is 1024x600 behind a bezel that hides about 115 px on the left and
95 on the right (docs/01), so the vendor draws everything in a fixed custom
viewport of 814x600 at x=115. That box is 4:3; a vertical (3:4) game forced
into it comes out squeezed to about 55 % of its proper height, which shows up
as "the screen looks squished and up/down movement is slower than left/right".
Letting RetroArch choose the aspect itself ("core provided") would centre on
the panel rather than on the opening, so the fix keeps the vendor viewport and
gives each vertical game an override with a 3:4 box inside the same opening at
the same pixel aspect: 458x600 at x=293. Horizontal games and TMNT are
untouched. `tools/retroarch/make-overrides.py` reads the DAT's screen
orientation for every zip in a folder and writes `<set>.cfg` for the vertical
ones; `tools/retroarch/overrides/MAME 2003-Plus/vertical.cfg.example` is the
file it writes. The files go to `~/.config/retroarch/config/MAME 2003-Plus/`
and apply when the game loads; moving `rgui_config_directory` there was the
one cfg edit (kill -9 first, as always).

## Restore to factory

```sh
adb shell "killall -9 retroarch
cp /userdata/.config/retroarch/retroarch.cfg.stock /userdata/.config/retroarch/retroarch.cfg
rm -rf /userdata/roms /userdata/.config/retroarch/config/remaps/MAME\ 2003-Plus/*.rmp /userdata/.config/retroarch/config/MAME\ 2003-Plus/*.cfg
sync"
adb reboot
```

(Or simply delete the cfg — `S22startup.sh` regenerates it from
`/etc/retroarch.cfg` at next boot. And `local/firmware/tmnt-stock/userdata.img`
can always be written back wholesale.)
