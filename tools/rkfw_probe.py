#!/usr/bin/env python3
"""Probe an RKFW firmware image: kernel, kernel config, device tree.

Companion to unsquash_rkfw.py (which handles the rootfs). Everything here works
on the raw .img with no external tools.

    python3 rkfw_probe.py summary  <image.img>          overview of what's inside
    python3 rkfw_probe.py kernel   <image.img> [out]    carve + gunzip vmlinux
    python3 rkfw_probe.py kconfig  <image.img> [out]    extract CONFIG_IKCONFIG blob
    python3 rkfw_probe.py dts      <image.img> [filter] dump device-tree nodes

`dts` takes an optional regex filtered against node paths, e.g.

    python3 rkfw_probe.py dts img.img 'usb|dwmmc|panel|opp'
"""
import re
import struct
import sys
import zlib


def load(path):
    with open(path, "rb") as f:
        return f.read()


# ---------------------------------------------------------------- boot / kernel

def find_boot_img(d):
    """Return (offset, kernel_size, second_size, page_size) of the real boot.img.

    Several 'ANDROID!' hits are bogus (they fall inside other data), so sanity
    check the header fields.
    """
    for m in re.finditer(b"ANDROID!", d):
        o = m.start()
        ks, _ka, rs, _ra, ss, _sa, _tags, ps = struct.unpack_from("<8I", d, o + 8)
        if 0 < ks < len(d) and ps in (2048, 4096) and rs < len(d) and ss < len(d):
            return o, ks, ss, ps
    raise ValueError("no plausible boot.img found")


def carve_kernel(d):
    o, ks, _ss, ps = find_boot_img(d)
    return d[o + ps:o + ps + ks]


def gunzip_biggest(blob):
    """zImage is a self-extracting wrapper; inflate its largest gzip member."""
    best = b""
    for m in re.finditer(b"\x1f\x8b\x08", blob):
        try:
            out = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(blob[m.start():])
        except zlib.error:
            continue
        if len(out) > len(best):
            best = out
    if not best:
        raise ValueError("no inflatable gzip stream in kernel")
    return best


def extract_kconfig(vmlinux):
    i = vmlinux.find(b"IKCFG_ST")
    if i < 0:
        raise ValueError("kernel was not built with CONFIG_IKCONFIG")
    return zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(vmlinux[i + 8:])


# ------------------------------------------------------------------ device tree

def parse_dtb(d, off):
    (_magic, total, off_s, off_str, _rsv, _ver, _lastver,
     _boot, size_str, size_s) = struct.unpack_from(">10I", d, off)
    blob = d[off:off + total]
    strs = blob[off_str:off_str + size_str]
    p, path, stack, nodes = off_s, [], [], []
    while p < off_s + size_s:
        tok = struct.unpack_from(">I", blob, p)[0]
        p += 4
        if tok == 1:                                  # FDT_BEGIN_NODE
            name = blob[p:blob.index(b"\0", p)].decode()
            p += (len(name) + 4) & ~3
            path.append(name)
            props = {}
            nodes.append(("/" + "/".join(path), props))
            stack.append(props)
        elif tok == 2:                                # FDT_END_NODE
            path.pop()
            stack.pop()
        elif tok == 3:                                # FDT_PROP
            ln, noff = struct.unpack_from(">II", blob, p)
            p += 8
            name = strs[noff:strs.index(b"\0", noff)].decode()
            val = blob[p:p + ln]
            p += (ln + 3) & ~3
            if stack:
                stack[-1][name] = val
        elif tok == 9:                                # FDT_END
            break
    return nodes


def find_dtbs(d, min_size=4096):
    out = []
    for m in re.finditer(b"\xd0\x0d\xfe\xed", d):
        total = struct.unpack_from(">I", d, m.start() + 4)[0]
        if min_size <= total < 4_000_000 and m.start() + total <= len(d):
            out.append((m.start(), total))
    return out


def kernel_dtb(d):
    """The biggest plausible DTB is the kernel's (u-boot's is much smaller)."""
    cands = find_dtbs(d)
    if not cands:
        raise ValueError("no device tree found")
    return max(cands, key=lambda c: c[1])[0]


def pretty(val):
    if val and all(31 < c < 127 or c == 0 for c in val):
        return val.rstrip(b"\0").replace(b"\0", b" ").decode(errors="replace")
    if len(val) == 4:
        return str(struct.unpack(">I", val)[0])
    if len(val) == 8:
        return str(struct.unpack(">Q", val)[0])
    return val.hex()


# ------------------------------------------------------------------------- main

def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    cmd, img = argv[1], argv[2]
    d = load(img)

    if cmd == "summary":
        o, ks, ss, ps = find_boot_img(d)
        print("boot.img      at 0x%x  kernel %d B  second(resource) %d B  page %d" % (o, ks, ss, ps))
        vm = gunzip_biggest(carve_kernel(d))
        ver = re.search(rb"Linux version [^\x00]{0,160}", vm)
        print("vmlinux       %d B" % len(vm))
        print("version       %s" % (ver.group(0).decode(errors="replace") if ver else "?"))
        try:
            cfg = extract_kconfig(vm).decode()
            print("kernel config %d B embedded (CONFIG_IKCONFIG)" % len(cfg))
        except ValueError as e:
            print("kernel config %s" % e)
        for o2, t in find_dtbs(d):
            nodes = parse_dtb(d, o2)
            root = dict(nodes[0][1]) if nodes else {}
            print("dtb           at 0x%-9x %7d B  %s" % (o2, t, pretty(root.get("model", b"?"))))
        sq = d.find(b"hsqs")
        if sq >= 0:
            inodes, _, bsize = struct.unpack_from("<IiI", d, sq + 4)
            used = struct.unpack_from("<Q", d, sq + 40)[0]
            print("squashfs      at 0x%x  %d inodes  block %d  %.1f MB used" % (sq, inodes, bsize, used / 1e6))
        cl = re.search(rb"CMDLINE:[^\x00]{0,400}", d)
        if cl:
            print("cmdline       %s" % cl.group(0).decode(errors="replace"))

    elif cmd == "kernel":
        out = argv[3] if len(argv) > 3 else "vmlinux"
        vm = gunzip_biggest(carve_kernel(d))
        open(out, "wb").write(vm)
        print("%s  %d bytes" % (out, len(vm)))

    elif cmd == "kconfig":
        out = argv[3] if len(argv) > 3 else "kernel.config"
        cfg = extract_kconfig(gunzip_biggest(carve_kernel(d)))
        open(out, "wb").write(cfg)
        print("%s  %d bytes" % (out, len(cfg)))

    elif cmd == "dts":
        filt = re.compile(argv[3], re.I) if len(argv) > 3 else None
        for path, props in parse_dtb(d, kernel_dtb(d)):
            if filt and not filt.search(path):
                continue
            print(path)
            for k, v in props.items():
                print("    %-28s %s" % (k, pretty(v)[:90]))

    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
