# Storage expansion: userdata 8 → 31.7 → 47.7 MiB (both executed)

> **Stage 2 (2026-09-03, later the same night):** the slim-rootfs flash —
> see the second half of this doc. Final state: **userdata 47.7 MiB, 41.8 MB
> free.**

2026-09-03. Third act of the Linux-host sessions (docs/09–12). The ROM
partition grew 4× without touching a byte of the rootfs.

## What was done

The stock layout wasted ~24 MiB: the rootfs partition was 80.75 MiB around a
56.3 MiB squashfs. The GPT was rewritten to shrink `rootfs` to 57 MiB (its
bytes never moved — same start sector 38912, same content) and grow
`userdata` into the freed space:

| part | stock (sectors) | new (sectors) | new size |
|---|---|---|---|
| rootfs | 38912 +165376 | 38912 **+116736** | 57 MiB |
| userdata | 204288 +16351 | **155648 +64991** | 31.7 MiB |

Everything else — disk GUID, partition names, and **every partition UUID** —
is byte-identical to stock. That last part is load-bearing: the kernel mounts
root by `root=PARTUUID=614e0000-0000` (prefix of the rootfs GPT UUID, set by
u-boot from the parameter block), so UUIDs must survive any re-tabling.

## Method (entirely over adb — no loader, no case opening)

1. New GPT authored on the Linux host with `sfdisk` against a scratch image
   (a scratch file), UUIDs pinned; primary (34 sectors @ LBA 0) and
   backup (33 sectors @ LBA 220639) extracted with dd. Backup GPT location
   verified identical to stock (`EFI PART` at LBA 220671 in both).
2. New userdata filesystem built on the Linux host: `mke2fs -t ext2 -L userdata -d
   <content>` (8123×4k blocks = 33,271,808 B, fits the 64,991-sector
   partition), populated with the live cabinet content (config + roms) pulled
   via adb tar, then `tune2fs -c 0 -i 0` (vendor convention).
3. On the cabinet: stop RetroArch, `umount /userdata`, then three dd writes to
   `/dev/rkflash0` — new userdata image at its new offset first, **GPT last as
   the commit point** (primary, then backup) — and reboot.
4. Kernel read the new table at boot; `S21mountall.sh` mounted the grown
   partition by partlabel; RetroArch came up with config and ROMs intact.

Result: `/userdata` 29.7 MiB, **27.6 MiB free** (was 7.0).

## Restore to stock layout

Recipe B in [docs/12-restore-runbook.md](docs/12-restore-runbook.md) plus
userdata: write back `gap-0.img` (contains the stock primary GPT), stock
`userdata.img` at sector 204288, and the stock backup GPT (`gap-220639.img`)
at 220639. Over adb while it boots; via loader `wl` below 32 MiB otherwise
(the backup GPT then goes in over adb after boot). The rootfs bytes were
never touched, so no rootfs restore is implied.

## Stage 2: slim rootfs (executed 2026-09-03)

The unused `mame2003` core, its 26 MB system dir, and artwork for six absent
games (14 entries total) were dropped and the squashfs rebuilt:
56.3 → **40.9 MiB** (`slim2.sqfs`, sha256 `17d7d3ed…`). Rebuild fidelity
hazards found and fixed during prep — **both would have flashed "successfully"**:

1. Non-root `unsquashfs` silently re-owned every file to uid 1000. Stock is
   uniformly root-owned (sole exception: an empty `/var/www` at 33/33), so
   `-force-uid 0 -force-gid 0` restores it.
2. Non-root extraction dropped the rootfs's only device node,
   `/dev/console` — recreated with `-p "dev/console c 622 0 0 5 1"`.

Entry-count math verified exact (3431 − 14 = 3417); compression options
matched to stock (xz, 131072); python/SDL2/evdev boot-menu stack verified
importable post-flash.

The write strategy was chosen deliberately. A loader-mode `wl` would have been
blind for 68% of the write (the >32 MiB loader-read cap makes deep writes
unverifiable until boot). Instead the rootfs was **written live over adb** —
kernel block path, trustworthy full-range — with every region hash-verified by
read-back *before* the new GPT was committed, so a bad write aborts with the
old table still valid. Two details matter: verification hashes the exact
written byte ranges (not whole partition devices, which would false-fail on a
live-drifting filesystem), and the caches were pre-warmed rather than dropped,
keeping busybox/adbd resident in RAM during the overwrite of the filesystem
they run from.

Sequence executed: stop RetroArch → dd slim squashfs to sector 38912 →
verify → dd new userdata to sector 122880 → verify → dd GPT primary+backup →
verify both → reboot. All four `OK`. Post-boot: p4 hash re-verified from the
new partition device, boot menu stack intact, ROMs/config carried over.

A **rescue image** was built first as insurance (`rescue.sqfs`,
2.8 MB, sha256 `df7815fe…`): busybox + glibc + adbd + the USB-gadget init
only. It fits entirely below the 32 MiB line, so it is loader-write-VERIFIABLE
— if the rootfs region is ever unbootable and adb is gone, flash it via
loader (`wl 38912 rescue.sqfs`, `rl`-verify, boot) to get a root adb shell
back, then restore everything over adb.

## Final partition map

| part | start | sectors | size |
|---|---|---|---|
| uboot | 8192 | 8192 | 4 MiB |
| trust | 16384 | 4096 | 2 MiB |
| boot | 20480 | 18432 | 9 MiB |
| rootfs | 38912 | 83968 | 41 MiB (squashfs 40.9) |
| userdata | 122880 | 97759 | **47.7 MiB (41.8 MB free)** |

## Restore to stock

Unchanged in principle: stock images + stock GPT from `tmnt-stock/`, all
writable over adb while it boots (recipe A in docs/12), or loader recipe B/C
otherwise. Note the stock rootfs image (165,376 sectors) overlaps the current
userdata region — a stock restore is all-or-nothing: rootfs + GPT + userdata
together.
