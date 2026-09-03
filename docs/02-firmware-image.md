# Firmware images

## The official update path is Rockchip's own flasher

Numskull's "Quarter Arcades – General Software Update" tutorial
(<https://www.youtube.com/watch?v=1ojowbNgQv4>) links a public Google Drive
folder containing exactly two files:

- `AndroidTool_Release_v2.65_En.zip` (110 MB) — Rockchip's **AndroidTool /
  RKDevTool** flashing utility
- `DriverAssitant_v4.5.zip` (9.4 MB) — Rockchip's USB driver installer

Both dated 2024-10-25. That is the standard Rockchip toolchain used to flash
Android/Linux images onto any Rockchip board or handheld. The same tool can
**read partitions back**, which is how a TMNT image would be dumped.

Update procedure is therefore the usual Rockchip dance: install the driver, put
the device into loader (or maskrom) mode over USB, load an `.img`, write.

The earlier generation worked differently — the 2019 Pac-Man firmware update was
a bespoke `PacmanUpdater.exe` on Windows, entered by **holding `Coin2` (the right
coin-door button) while plugging in the USB cable**, and it needed a *data*
micro-USB cable (the bundled charge cable didn't work). Two variants were
offered, "5 lives" and "3 lives" — i.e. different romset builds. That page is
gone from numskull.com; archived copy in [05-sources.md](05-sources.md). The
`.zip` payloads themselves were never archived.

Support pages have moved: `quarterarcades.com` is now a password-locked Shopify
store redirecting to `numskull.com`, and the old firmware page
`quarterarcades.com/pages/support` rendered its body client-side, so the Wayback
snapshots are empty shells. Firmware links per cabinet were posted there and in
YouTube video descriptions.

## Known published images

| Cabinet(s) | File | Size |
|---|---|---|
| Space Invaders | `SI-LBQ1295A-2023-12-22-5dB-Version 3.img` | 73.9 MB |
| Space Invaders Part II | `SI2-LBQ1295B-2023-12-22-5dB-Version 3.img` | 73.9 MB |

Posted 2024-01-19 in a Drive folder linked from "Quarter Arcades Space Invaders
new Sound fix Firmware" (<https://www.youtube.com/watch?v=X2fXn4mFhCE>).

Not redistributed here. Owners of the corresponding cabinet can obtain it via Numskull's official update instructions; verify a downloaded copy against:

```
SI-LBQ1295A-2023-12-22-5dB-Version3.img
sha256 de3a475ebf5dc8d32040cf4f6f036b7d991c25b0deebe13f9b52a419441e2019
```

Working copies belong in `local/firmware/`, which is git-ignored.

**I've not been able to identify a published TMNT image.** So for now the
recovery baseline for this cabinet is its own dump, taken over adb (docs/09)
and kept in `local/firmware/tmnt-stock/` — plus, ideally, an official image
from Numskull support if one turns out to exist.

## RKFW container format

```
00000000  52 4b 46 57  "RKFW"   magic
00000004  ..                    header len / version
0000000c  ..                    build date (BCD)
00000060  42 4f 4f 54  "BOOT"   embedded bootloader record
0002a9b4  52 4b 41 46  "RKAF"   embedded update.img (partition archive)
```

Inside the RKAF: `MiniLoaderAll.bin`, `parameter`, `uboot.img`, `trust.img`,
`boot.img`, `kernel.img`, `resource.img`, `rootfs.img`, `oem.img`, `misc.img`,
`recovery.img`. Notably **absent**: `system.img` / `vendor.img` — this is a Linux
image, not Android, despite being flashed by a tool called AndroidTool.

Useful offsets in the Space Invaders image:

| Offset | What |
|---|---|
| `0x2a9b4` | RKAF header |
| `0xe099b4` | kernel DTB (`rockchip,rk3128`) |
| `0xe389b4` | **squashfs rootfs** (magic `hsqs`, v4.0, xz, 3432 inodes, 128 KB blocks, `bytes_used` 57,314,636) |

## Reading a rootfs on macOS

macOS ships no `unsquashfs`, and Homebrew's `squashfs` was not installed here, so
`tools/unsquash_rkfw.py` implements just enough squashfs 4.0 to walk the tree and
extract files, using stdlib `lzma`. It finds the squashfs offset itself by
scanning for `hsqs`, so it works on any RKFW image of this shape.

```bash
IMG=local/firmware/SI-LBQ1295A-2023-12-22-5dB-Version3.img
python3 tools/unsquash_rkfw.py list  $IMG '/etc/*'
python3 tools/unsquash_rkfw.py cat   $IMG /etc/init.d/S22startup.sh
python3 tools/unsquash_rkfw.py dump  $IMG /tmp/out /opt/uiconfig/main.py /etc/retroarch.cfg
python3 tools/unsquash_rkfw.py index $IMG > listing.json
```

Committed derived data, in `data/`:

- `si-rootfs-tree.txt` — full 3,433-entry path listing
- `si-rootfs-filelist.json` — same, with inode refs, for scripted extraction

Path listings are facts about the device; the file *contents* are Numskull's and
are not committed. Extract them into the git-ignored `local/` when you need to
read along with the docs. `/etc/shadow` in particular is worth not keeping: root
has an MD5-crypt hash set, and it is of no use here since ADB gives a root shell
without it.

## Dumping your own cabinet — the method that works

Forget Windows/AndroidTool for *reading*: the cabinet gives a root adb shell
from any Linux host (docs/09), and `tools/adb-dump.sh` takes a complete,
hash-verified dump of every partition and both GPT regions from normal boot,
writing nothing. **Do not dump via `rkdeveloptool rl`** — loader reads
silently return filler past 32 MiB on this hardware (docs/07, docs/12).

Rockchip maskrom mode makes bad flashes recoverable and is confirmed reachable
on this board (`adb reboot loader`, then `rkdeveloptool rd 3`); the full
recovery ladder and its sharp edges are in docs/10 and docs/12.
