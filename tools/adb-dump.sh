#!/bin/sh
# Full read-only flash backup over adb, no loader mode needed.
#
# Works around this adbd's missing exec-out service: each partition is copied
# to the cabinet's tmpfs /tmp (RAM only — nothing is written to flash), pulled,
# hash-verified against the device-side sha256, then deleted from /tmp.
#
#   sh adb-dump.sh <outdir>
#
# Produces <outdir>/{uboot,trust,boot,rootfs,userdata}.img, gap dumps for the
# unpartitioned regions of rkflash0, partmap.txt, and SHA256SUMS.
set -eu
OUT="${1:?usage: adb-dump.sh <outdir>}"
mkdir -p "$OUT"; cd "$OUT"

echo "== partition map (512-byte sectors)"
adb shell 'for p in /sys/block/rkflash0/rkflash0p*; do echo "$(basename "$p") $(cat "$p"/start) $(cat "$p"/size)"; done; echo "rkflash0 0 $(cat /sys/block/rkflash0/size)"' | tr -d '\r' > partmap.txt
cat partmap.txt

pull_verify() { # $1 = remote tmp file, $2 = local name
    want=$(adb shell "sha256sum $1" | tr -d '\r' | awk '{print $1}')
    adb pull "$1" "$2" >/dev/null
    adb shell "rm $1"
    got=$(sha256sum "$2" | awk '{print $1}')
    if [ "$want" = "$got" ]; then
        echo "OK  $2  $got"
    else
        echo "HASH MISMATCH on $2: device=$want host=$got" >&2; exit 1
    fi
}

i=1
for name in uboot trust boot rootfs userdata; do
    echo "== rkflash0p$i -> $name.img"
    adb shell "cat /dev/rkflash0p$i > /tmp/d.img"
    pull_verify /tmp/d.img "$name.img"
    i=$((i+1))
done

echo "== unpartitioned gaps"
# Everything on rkflash0 not covered by p1..p5 (parameter area lives here).
sort -k2 -n partmap.txt | awk '
    BEGIN { pos=0 }
    $1=="rkflash0" { total=$3; next }
    { if ($2 > pos) print pos, $2-pos; pos=$2+$3 }
    END { if (total > pos) print pos, total-pos }' | while read -r start count; do
    echo "   gap @sector $start, $count sectors"
    adb shell "dd if=/dev/rkflash0 of=/tmp/d.img bs=512 skip=$start count=$count 2>/dev/null"
    pull_verify /tmp/d.img "gap-$start.img"
done

echo "== whole-device hash (for the record; read directly, nothing staged)"
adb shell "sha256sum /dev/rkflash0" | tr -d '\r' | tee rkflash0.device.sha256

sha256sum ./*.img > SHA256SUMS
echo "== done"; ls -l
