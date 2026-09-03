# Restore runbook

The definitive recovery recipes, written after every mechanism in them was
exercised on the hardware (2026-09-02/03). Read docs/10 for how these facts
were established.

## Proven facts this runbook rests on

- **adb reads are trustworthy over the full flash** (two independent paths
  agreed byte-for-byte). `tools/adb-dump.sh` is the canonical backup method.
- **Loader writes work**: `rkdeveloptool wl` wrote the `trust` partition and
  the result verified three ways (loader read-back, reboot, adb hash).
- **Loader reads are valid only below 32 MiB** (LBA < 65536). Past that they
  silently return `0xCC` filler. Never trust a deep `rl`.
- **Only the vendor loader works.** rkbin's generic RK3128 usbplug binaries
  (v2.63, v2.65-SLC) download fine but fail ALL flash reads on this board and
  wedge until power-cycled. The vendor `MiniLoaderAll` (extracted from the SI
  image, sha256 `345c4c3d…7400e46`) is archived at
  `local/firmware/MiniLoaderAll-SI-vendor.bin` and on the Linux host at
  `<backup-dir>/MiniLoaderAll-SI-vendor.bin`. Guard it.
- Deep (>32 MiB) loader **writes** are vendor-demonstrated (AndroidTool flashes
  the full image on SI cabinets) but not exercised here; after any deep write,
  **verify by booting and hashing over adb** before trusting it.

## The backup

`tmnt-stock/`: 5 partitions + both GPT gaps + `SHA256SUMS` + `partmap.txt`,
present on the Linux host (`<backup-dir>/tmnt-stock/`) and a second machine
(`local/firmware/tmnt-stock/`). `userdata.img` is a point-in-time snapshot
(live ext2 metadata drifts ~10 bytes); everything else is byte-exact.

Partition map (512-byte sectors) — stock:

| region | start | count |
|---|---|---|
| GPT (primary) | 0 | 8192 (gap-0.img; table itself is 0–33) |
| uboot | 8192 | 8192 |
| trust | 16384 | 4096 |
| boot | 20480 | 18432 |
| rootfs | 38912 | 165376 |
| userdata | 204288 | 16351 |
| GPT (backup) | 220639 | 33 |

## Failure mode → recipe

### A. Software mess, Linux still boots (adb works)

Restore any partition over adb — full range, no loader needed:

```sh
adb push local/firmware/tmnt-stock/<part>.img /tmp/p.img   # if it fits in RAM (<100 MB free)
adb shell "dd if=/tmp/p.img of=/dev/block/by-name/<part> conv=fsync"
adb shell "sha256sum /dev/block/by-name/<part>"             # compare to SHA256SUMS
```

For userdata-only trouble (broken RetroArch config), skip images entirely:
`adb shell "killall -9 retroarch; cp /userdata/.config/retroarch/retroarch.cfg.stock /userdata/.config/retroarch/retroarch.cfg; sync"` and reboot —
or just delete the cfg; `S22startup.sh` regenerates it.

### B. Linux won't boot, u-boot alive (screen dark/stuck, but `adb reboot loader` had been possible → enter loader by power-cycling; u-boot falls into rockusb if boot fails, or use the hidden SARADC key)

Everything that decides whether Linux boots (`uboot`, `trust`, `boot`, GPT)
lives **below 32 MiB**, where loader reads AND writes are proven:

```sh
R=~/rkdeveloptool/rkdeveloptool                    # on the Linux host
$R ld                                              # expect Loader or Maskrom
$R wl 8192  tmnt-stock/uboot.img
$R wl 16384 tmnt-stock/trust.img
$R wl 20480 tmnt-stock/boot.img
$R rl 8192 8192  /tmp/v1.img && sha256sum /tmp/v1.img   # verify each (<32 MiB → reliable)
$R rd
```

GPT repair: `wl 0 tmnt-stock/gap-0.img` (primary; first 8192 sectors include
it) — the backup GPT at 220639 is >32 MiB, write it over adb after boot.

### C. u-boot dead too (no loader PID on the bus)

A corrupt u-boot drops the bootROM into maskrom by itself. Then:

```sh
$R ld                                              # expect Maskrom
$R db MiniLoaderAll-SI-vendor.bin                  # the vendor loader; generic rkbin loaders are incompatible
sleep 5
# now as in (B); for rootfs (deep write):
$R wl 38912 tmnt-stock/rootfs.img                  # vendor-demonstrated path
$R rd                                              # then boot and verify over adb:
adb shell "sha256sum /dev/block/by-name/rootfs"
```

If a deep write must be verified before daring a boot, there is no loader way —
that is the accepted residual risk, bounded by: writes below 32 MiB are
verifiable, so the machine can always be brought back to a bootable state
where adb verifies the rest.

### D. Wedged usbplug (rkdeveloptool `rd` says "Reset Device failed!")

Power-cycle at the switch. RAM-only condition; flash is untouched.

## Rules

1. Never `rl`-dump for backup purposes. adb only.
2. Never flash anything not hash-checked against `SHA256SUMS` first.
3. After any deep (>32 MiB) write: boot, `sha256sum` the partition over adb.
4. The vendor MiniLoaderAll is irreplaceable until Numskull publishes a TMNT
   image — keep both archived copies.
