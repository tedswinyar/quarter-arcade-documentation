# Software stack

Originally read out of the Space Invaders rootfs; since verified on the
running TMNT cabinet, which is the same platform build with `game=tmnt`
(docs/09). Vendor files are **described, not reproduced** — this repo carries
no firmware content. Extract your own copies to read along:

```bash
python3 tools/unsquash_rkfw.py dump <image.img> /tmp/out /etc/init.d/S22startup.sh
```

## Boot chain

BusyBox init → `/etc/init.d/rcS` runs `S??*` in order:

| Script | Purpose |
|---|---|
| `S01logging` | syslog |
| `S10udev` | udev |
| `S20urandom` | entropy |
| `S21mountall.sh` | mounts `/etc/fstab` incl. `/userdata` |
| **`S22startup.sh`** | **product startup: config UI, then RetroArch** |
| `S40network` | `ifup -a` — does nothing, there is no `/etc/network/interfaces` |
| `S41dhcpcd` | dhcpcd |
| **`S50sshd`** | generates host keys and starts `sshd` |
| **`S50usbdevice`** | Rockchip USB gadget setup — **starts `adbd`** |
| `S80dnsmasq` | dnsmasq (vendor BSP leftover) |
| `S99_auto_reboot` | Rockchip test-suite leftover |

`/etc/inittab` also carries the stock BusyBox `::respawn:-/bin/sh` entry — i.e. an
**unauthenticated root shell on the console**, which is `ttyFIQ0` per the
kernel cmdline. Serial header access = instant root, no password. The `getty`
line for `ttyFIQ0` is commented out, so the respawned `-/bin/sh` is what you get.

Other vendor leftovers present: `/rockchip_test/` (including `chromium_test.sh`),
Python 3.7 with PySDL2 and evdev, `mount.exfat` / `mount.ntfs`.

## `/etc/init.d/S22startup.sh` — the startup sequence, in ~40 lines

What the `start` case does, in order:

1. sets `HOME=/userdata`, and a shell variable `game` to the romset name — for
   this image, `game=sitv`
2. `udevadm trigger`
3. runs `python /opt/uiconfig/main.py $game` (the hidden config UI — blocks until
   it exits)
4. backgrounds `audio_volume.py` (volume-knob poller)
5. if `/userdata/.config/retroarch/retroarch.cfg` does not exist, copies
   `/etc/retroarch.cfg` there and strips comments and blank lines with `sed`
6. mounts an overlayfs at `/userdata/system`, with `/usr/share/libretro/system`
   as the read-only lower layer and `/userdata/.config/retroarch/system` as the
   writable upper layer
7. backgrounds RetroArch, equivalent to:

```
retroarch -c /userdata/.config/retroarch/retroarch.cfg \
          -L /usr/lib/libretro/mame2003plus_libretro.so \
             /usr/share/libretro/$game.zip
```

Five things worth noting:

1. **`game=sitv`** is the only per-cabinet difference in this script. `sitv` is
   the MAME romset name for Space Invaders (TV version). TMNT would be `tmnt`;
   Turtles in Time would be `tmnt2`.
2. The content argument is a **plain MAME romset zip on the filesystem**:
   `/usr/share/libretro/sitv.zip`. There is no DRM, no signing, no container.
3. **`retroarch.cfg` is user-writable and persistent.** It is copied from `/etc`
   into `/userdata/.config/retroarch/` only *if missing*, then comments and blank
   lines are stripped. Anything you set there survives reboots without touching
   the read-only rootfs.
4. An **overlayfs** puts `/usr/share/libretro/system` (read-only, lower) under
   `/userdata/.config/retroarch/system` (writable, upper) at `/userdata/system` —
   that is how MAME nvram / hiscores / cheats persist.
5. RetroArch runs as a bare fullscreen process. There is no launcher, no
   playlist, no menu shown.

## RetroArch

- `/usr/bin/retroarch` and `/usr/local/bin/retroarch`
- Cores: `/usr/lib/libretro/mame2003plus_libretro.so` and
  `mame2003_libretro.so` → **MAME 0.78-era romsets** are the compatible set
- Support data under `/usr/share/libretro/system/mame2003-plus/`:
  `mame2003-plus.xml`, `catver.ini`, `cheat.dat`, `hiscore.dat`, `history.dat`,
  `samples/invaders.zip`, and artwork overlays (`blueshrk`, `frogs`, `omegrace`,
  `skydiver`, `solarq`, `warrior`)
- Shaders: `zfast-crt`, `flip-horizontal`, and the active one,
  `crt-aperture.glsl`
- **Per-game shader configs for other cabinets are present in this image** —
  `config/MAME 2003-Plus/qix.glslp` and `zookeep.glslp` — proving one shared
  platform build across the whole Quarter Arcades range
- Full joypad autoconfig set (`/usr/share/libretro/autoconfig`) including every
  8BitDo profile and the vendor's own `Dashine_Arcade_Joystick.cfg` (the panel's
  binding profile — docs/11). This is how USB pads work on units whose front
  ports function (docs/11: dead on this one)

The shipped `/etc/retroarch.cfg` is RetroArch's own skeleton config with 20
settings actually uncommented. The ones that matter:

| Setting | Value |
|---|---|
| `libretro_path` | `/usr/lib/libretro/mame2003plus_libretro.so` |
| `video_shader` | `/usr/share/libretro/shaders/crt-aperture.glsl` |
| `video_allow_rotate` / `video_rotation` / `screen_orientation` | `true` / `1` / `1` |
| `video_scale` / `video_aspect_ratio` / `aspect_ratio_index` | `3.0` / `-1.0` / `0` |
| `video_threaded` | `true` |
| `input_max_users` | `8` |
| `system_directory` | `/userdata/system` (the overlay mount) |
| `assets_directory` | `/usr/share/libretro/assets` |
| `joypad_autoconfig_dir` | `/usr/share/libretro/autoconfig` |
| `input_remapping_directory` | `/usr/share/libretro/config/remaps` |
| `video_shader_dir` / `rgui_config_directory` | `/usr/share/libretro/shaders` / `/usr/share/libretro/config` |
| `video_font_enable`, `menu_enable_widgets`, every `notification_show_*` | `false` |

`video_rotation = 1` / `screen_orientation = 1` rotate for vertical games in
the SI image; the TMNT runs unrotated with a bezel-matched custom viewport
(verified — docs/01). `input_max_users = 8` covers the 4-player panel plus
USB pads. Note `assets_directory` points at a real RetroArch
assets tree, so the RGUI menu has the files it needs to render if enabled.

## The hidden boot menu

`python /opt/uiconfig/main.py $game` runs *before* RetroArch and exits
immediately unless a button combination is held. Its gate check (`UI.__check`)
opens `/dev/input/event0` through `event3` via python-evdev and returns true only
if `BTN_A` is in the currently-held keys of **both `event0` and `event1`**.

So: **hold the A/attack button on the P1 *and* P2 controls at power-on** — and
you get an SDL2 menu (PySDL2 + SDL_ttf, fullscreen, Cascadia Mono).

Contents, in the order they are appended:

- **Per-game MAME cheats**, parsed out of `/opt/uiconfig/cheat.dat` filtered to
  the current `game` (so what you see depends on the cabinet)
- **Enable/Disable CRT** — toggles `video_shader_enable` in the *userdata* copy
  of `retroarch.cfg` via `sed`
- **Start Game** — writes selected cheats to
  `/userdata/.config/retroarch/system/mame2003-plus/cheat.dat` and exits

Navigation: joystick left/right/up/down (`BTN_LEFT`/`BTN_RIGHT`/`BTN_BACK`/
`BTN_FORWARD`/`ABS_HAT0X`/`ABS_HAT0Y`/`BTN_C`), `BTN_A` to select. There is also
a `--nocheck` flag that skips the button gate entirely, useful once you have a
shell.

I found no mention of this menu in any manual, review, or forum post.

## Access surfaces

| Surface | State in stock firmware | Needs case open? |
|---|---|---|
| **ADB over USB** | **enabled.** `/etc/init.d/.usb_config` contains `usb_adb_en`; `S50usbdevice` then sets `ADB_EN=on` and runs `start-stop-daemon --start --background --exec /usr/bin/adbd` | no |
| Serial console | root shell, no password (`::respawn:-/bin/sh` on `ttyFIQ0`) | yes |
| `sshd` | starts, generates host keys — but **no network interface exists** (no wifi firmware, no `interfaces` file, ethernet unpopulated). Root also has an MD5-crypt password set | n/a |
| USB mass storage | `usbmount` `ENABLED=1`, mountpoints `/media/usb0`…`usb7`, filesystems `vfat ext2 ext3 ext4 hfsplus ntfs exfat fuseblk` | no |
| USB gadget UMS/MTP | present in `S50usbdevice` but off (`UMS_EN=off`, `MTP_EN=off`) | no |

`/etc/passwd` is stock buildroot: `root:x:0:0:root:/root:/bin/sh`, plus daemon
accounts and an `sshd` priv-sep user. Nothing product-specific.
