# Sources

Gathered 2026-09-01.

## Primary — vendor

| Source | Value |
|---|---|
| [TMNT product page](https://numskull.com/products/official-teenage-mutant-ninja-turtles-quarter-size-arcade) (JSON via `…/<handle>.json`) | Full specs: 6" TFT 4:3, 4× front USB ports for gamepads, USB-C power, internal Li battery, 3 W speaker, "original TMNT arcade ROM", dimensions |
| [Numskull technical support](https://numskull.com/pages/technical-support) | Warranty voided if "modified, opened, altered"; manuals said to live on product pages (they don't, for the arcades) |
| ["Quarter Arcades – General Software Update"](https://www.youtube.com/watch?v=1ojowbNgQv4) | Links the Drive folder holding **AndroidTool 2.65 + DriverAssistant 4.5** — the Rockchip toolchain finding |
| [Archived 2019 Pac-Man firmware page](http://web.archive.org/web/20231204132943/https://numskull.com/quarter-arcades-%C2%BC-scale-pac-man-arcade-cabinet-firmware-update/) | Old-generation update method: `PacmanUpdater.exe`, hold `Coin2` while plugging in USB, data cable required, 3-lives/5-lives builds. Payload zips were not archived |
| [Space Invaders sound-fix firmware video](https://www.youtube.com/watch?v=X2fXn4mFhCE) | Links the Drive folder with `SI-LBQ1295A` / `SI2-LBQ1295B` `.img` files — the images analysed here |
| `quarterarcades.com` | Password-locked, moved to numskull.com. `pages/support` (the firmware page) rendered client-side, so Wayback snapshots are empty |

## Primary — the firmware itself

Everything in [01-hardware.md](01-hardware.md) and
[03-software-stack.md](03-software-stack.md) is derived from
`SI-LBQ1295A-2023-12-22-5dB-Version 3.img`, read with `tools/unsquash_rkfw.py`.
This is the strongest evidence in the project and does not depend on anyone's
review or forum post.

## Secondary — press / reviews

- [Time Extension: all available Quarter Arcades](https://www.timeextension.com/guides/numskull-quarter-arcades-all-available-games-and-where-to-buy-them) — range, prices, "play original arcade ROMs", USB controller support
- [GenXGrownUp: BurgerTime new firmware](https://genxgrownup.com/burger-time-quarter-scale-arcade-cabinet-new-firmware-now-available/) (Aug 2026) — firmware updates are ongoing; points at `quarterarcades.com/pages/support`
- ["I Broke my Review Unit… But I Fixed It!" — TMNT](https://www.youtube.com/watch?v=Bc_gzM2Q2nk) — **TMNT teardown and LCD replacement**, generic AliExpress panel, explicit warranty warning
- ["Can Numskull 1/4 Scale PAC-Man Arcade mod into Raspberry Pi 3B+?"](https://www.youtube.com/watch?v=kXteBi0L7AA) — early teardown/Pi-conversion look
- ["Numskull Pac-man quarter arcade mod"](https://www.youtube.com/watch?v=iCRe6jxNKg0) — internal powered USB hub, direct-to-PCB power lead
- ["Numskull Quarter Arcade – Factory Returns – What's inside?"](https://www.youtube.com/watch?v=hjHnhZ-iweI) — teardown of factory-return units

## Community (not yet mined)

- **[Facebook group "Numskull Quarter Arcade, modify, repair, discuss"](https://www.facebook.com/groups/697649206703062/)** — by name, the most likely place any modding knowledge exists
- [Facebook "Numskull Quarter Arcades Fan Club"](https://www.facebook.com/groups/306414509947612/) (not run by Numskull; referenced in their own 2019 firmware post)
- [r/QuarterArcades](https://www.reddit.com/r/QuarterArcades/) — active, carries firmware-update posts (e.g. "BurgerTime Firmware Update")
- [ukVAC thread on a Quarter Arcade screen fault](https://www.ukvac.com/forum/threads/quarter-arcade-screen.83402/)
- AtariAge "Mini Arcade Modding" thread: <https://forums.atariage.com/topic/279605-mini-arcade-modding/>

## Research leads not yet followed

- **FCC filings**: internal photos would independently confirm the board for
  US-sold cabinets (`fccid.io` was unreachable when tried; retry elsewhere).
- The firmware images referenced above come from the public Drive folder that
  Numskull's own update video links; they are for owners servicing the
  corresponding cabinet and are not redistributed here.

## Searched for, not yet found

Absence of evidence, not evidence of absence — these are things I looked for
and couldn't locate, updated if that changes:

- Any published TMNT firmware image
- Any custom firmware, dump, romset-swap, or "add games" project for Quarter
  Arcades
- Any mention of the hidden boot menu
- Any reference to the `LBQ1295` board code
