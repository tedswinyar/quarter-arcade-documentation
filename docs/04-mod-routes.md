# Customisation routes — the survey, with outcomes

The 2026-09-01 survey of what was possible, updated with what each route
turned out to be worth once the hardware could be tested. The chosen route is
implemented in docs/11 (ROM loading) and docs/13 (storage); dead ends are
autopsied in docs/07.

## Tier 0 — free, reversible, no tools

1. **The hidden boot menu** — hold attack on the blue *and* yellow positions
   at power-on: per-game MAME cheats, CRT filter toggle, Start Game
   (docs/03). *Verified working, including after the slim-rootfs flash.*
2. **USB gamepads in the front ports** — real feature, dead ports on this
   unit (docs/11). Repairable; ports live behind the coin doors, so possibly
   without touching the warranty seal.
3. **Stay current on official firmware** — per-cabinet images fix real bugs
   (Pac-Man 1.3.0: freezing/credits/sound; SI: sound fix; BurgerTime updated
   Aug 2026). I have not identified a published TMNT recovery image.
4. **Accessories**, if the goal is the diorama: stool, carpet, ¼-scale props,
   the official USB controller.

## Tier 1 — adb over USB-C ← **the chosen route**

`adbd` runs in stock firmware as root, no auth. From a Linux host this is a
full root shell with zero case opening and zero flashing. Everything the
project needed came through it:

- **Persistent config**: `/userdata/.config/retroarch/retroarch.cfg` survives
  reboots (rootfs only seeds it when missing). Binding a menu toggle to panel
  buttons turned RetroArch's file browser into the game picker — docs/11.
- **ROM storage**: `/userdata` (grown to 47.7 MiB — docs/13).
- **Full flash backup**, read-only, from normal boot — docs/09, tools/adb-dump.sh.
- **Deliberate loader/maskrom entry** (`adb reboot loader`, `rd 3`) — docs/10.
- Hidden menu on demand: `python /opt/uiconfig/main.py <game> --nocheck`.

Limit, confirmed: `S22startup.sh` lives in the read-only squashfs, so *boot*
behaviour can't change from userdata alone — but config-level changes turned
out to be enough for the goal.

## Tier 2 — reflash a modified image

Executed, in a smaller form than originally sketched: not to add content but
to **shrink** — the unused `mame2003` core and unused support data were dropped
and the freed partition space given to `userdata` (docs/13). Key facts learned:

- Only the **vendor's own loader** can address this NAND, and its reads return filler
  past 32 MiB (docs/07, docs/12). The safe flash path is writing over adb from
  the running system with hash verification before committing the GPT.
- `uboot`/`trust`/`boot` were never touched; restore is documented and
  partially rehearsed (docs/12).
- A fully custom rootfs (extra cores — FBNeo, consoles; modified startup;
  stock-when-no-marker-present tricks) remains possible with the same
  toolchain, and remains unnecessary for the current goal.

## Tier 3 — gut it and fit a Pi: set aside

The RK3128 is already Pi-2-class silicon running RetroArch (docs/06), so a Pi
swap buys a friendlier userland at the cost of the original hardware and the
collectible value. Precedents exist (Pi conversion:
youtube.com/watch?v=kXteBi0L7AA; internal powered hub:
youtube.com/watch?v=iCRe6jxNKg0). Only rational if the goal is a generic mini
cabinet.

## Set aside: using it as a small server

The kernel would cooperate — USB Ethernet drivers galore, bridge/tun/
netfilter/cgroups, even nfsd, all built in — and it would do DNS/Syncthing/
MQTT at Pi Zero 2 W speed. Dropped because the platform taxes everything: no
network hardware, no HDMI, no GPIO, soldered NAND, no package manager, a
community of one. Two clinchers: it is a **sealed wooden box with a lithium
battery and no ventilation** (permanent float charge ages the cell exactly
where you least want that), and `userdata` is small NAND, so write-heavy loads
need USB anyway. A £15 Pi does the job better.

## Why "mostly stock" remains the frame

- £250–350 licensed collectible; signed editions more.
- Opening the case voids the Rubber Road warranty — still never done here.
- There was **no public modding scene** when this started: no dumps, no
  rebuild scripts, nobody to unbrick you. This repo is, as far as known, the
  first public documentation; the safety nets (backups, restore runbook,
  rescue image) had to be built before anything was changed, and were.

## Legal / ethical line

MAME romsets you are not entitled to are not part of this project. Nothing
copyrighted is committed; firmware dumps and vendor files stay in the
git-ignored `local/` as a recovery and interoperability baseline only.
