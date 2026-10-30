# Storage layout: slim rootfs, 47.7 MiB userdata

The stock layout wastes most of the flash: an 80.75 MiB rootfs partition
around a 56.3 MiB squashfs, and an 8 MiB `userdata` with 7 MiB free for
anything an owner adds. Both were changed, entirely over adb, without opening
the case or using loader mode. Current layout (512-byte sectors):

| part | start | sectors | size |
|---|---|---|---|
| uboot | 8192 | 8192 | 4 MiB |
| trust | 16384 | 4096 | 2 MiB |
| boot | 20480 | 18432 | 9 MiB |
| rootfs | 38912 | 83968 | 41 MiB (squashfs 40.9 MiB) |
| userdata | 122880 | 97759 | **47.7 MiB (41.8 MB free)** |

Disk GUID, partition names and every partition UUID are byte-identical to
stock. That is load-bearing: the kernel mounts root by
`root=PARTUUID=614e0000-0000`, a prefix of the rootfs GPT UUID set by u-boot
from the parameter block, so UUIDs must survive any re-tabling.

## What was removed from the rootfs

The unused `mame2003` core, its 26 MB system directory, and artwork for six
games not on this cabinet: 14 entries, 56.3 → 40.9 MiB. Nothing else changed;
the boot-menu stack (python, SDL2, evdev) and everything the game needs are
intact.

## Method

1. **Author the new GPT on a PC** with `sfdisk` against a scratch image, UUIDs
   pinned to the stock values; extract the primary table (34 sectors at LBA 0)
   and the backup (33 sectors at LBA 220639) with `dd`. The backup GPT
   location is the same as stock (`EFI PART` at LBA 220671).
2. **Build the new userdata filesystem on the PC**: `mke2fs -t ext2 -L userdata
   -d <content>` populated with the live cabinet content (config and roms,
   pulled over adb with tar), then `tune2fs -c 0 -i 0` as the vendor does.
3. **Rebuild the squashfs on the PC** (see the fidelity hazards below), with
   compression matched to stock (xz, 128 KiB blocks).
4. **Write over adb from the running system**, in this order: stop RetroArch,
   `dd` the squashfs to sector 38912, verify, `dd` the userdata image to its
   new offset, verify, `dd` the GPT primary and backup, verify both, reboot.
   The GPT is the commit point: until it is written the old table is valid and
   a bad write aborts cleanly.

Why a live write rather than loader mode: a loader `wl` would be blind for
most of the write, since loader reads are unverifiable past 32 MiB (docs/10),
whereas the kernel block path reads back the full range. Two details matter.
Verification hashes the exact written byte ranges, not whole partition
devices, which would false-fail on a live-drifting filesystem. And the page
cache was pre-warmed rather than dropped, keeping busybox and adbd resident in
RAM while the filesystem they run from was overwritten underneath them.

## Rebuild fidelity hazards

Both of these produce an image that flashes "successfully" and is wrong:

1. Non-root `unsquashfs` silently re-owns every file to the extracting user.
   Stock is uniformly root-owned (the sole exception is an empty `/var/www`
   at 33/33), so rebuild with `-force-uid 0 -force-gid 0`.
2. Non-root extraction drops the rootfs's only device node, `/dev/console`.
   Recreate it with `-p "dev/console c 622 0 0 5 1"`.

Check the entry count against the original minus what you removed before
flashing (here 3431 − 14 = 3417).

## Rescue image

Build this before touching the rootfs. `rescue.sqfs` (2.8 MB) is busybox,
glibc, adbd and the USB-gadget init only. It fits entirely below the 32 MiB
line, so it can be written and read back via loader mode: if the rootfs region
is ever unbootable and adb is gone, `wl 38912 rescue.sqfs`, verify with `rl`,
boot, and a root adb shell is back for restoring everything else over adb.

## Restore to stock

Stock images plus the stock GPT from the backup (`tmnt-stock/`), all writable
over adb while the cabinet boots (recipe A in docs/12), or via loader recipes B
and C otherwise. The stock rootfs image (165,376 sectors) overlaps the current
userdata region, so a stock restore is all-or-nothing: rootfs, GPT and
userdata together.
