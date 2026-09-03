#!/usr/bin/env python3
"""Read the squashfs rootfs out of a Rockchip RKFW firmware image, no deps.

macOS has no unsquashfs and the Quarter Arcades rootfs is squashfs 4.0/xz, so
this parses the format directly with stdlib lzma. Enough of squashfs is
implemented to list the tree and pull individual files out; it does not write
anything back.

    python3 unsquash_rkfw.py list   <image.img> [glob]
    python3 unsquash_rkfw.py cat    <image.img> /etc/init.d/S22startup.sh
    python3 unsquash_rkfw.py dump   <image.img> <destdir> /etc/... [/etc/... ...]

The squashfs offset inside the .img is found by scanning for the 'hsqs' magic,
so this works on any RKFW image with a squashfs rootfs partition.
"""
import fnmatch
import json
import lzma
import os
import struct
import sys


class SquashFS:
    def __init__(self, path, offset=None):
        self.f = open(path, "rb")
        self.off = offset if offset is not None else self._find_offset()
        sb = self._rd(0, 96)
        (self.magic, self.inodes, _mkfs, self.bsize, _frags, self.comp,
         _blog, self.flags, _ids, self.vmaj, self.vmin, self.root_ref,
         self.bytes_used, _id_start, _xattr_start, self.inode_start,
         self.dir_start, self.frag_start, _lookup) = struct.unpack_from(
            "<IIIIIHHHHHHQQQQQQQQ", sb, 0)
        if self.magic != 0x73717368:
            raise ValueError("no squashfs superblock at offset 0x%x" % self.off)
        self._meta = {}

    def _find_offset(self):
        self.f.seek(0)
        data = self.f.read()
        i = data.find(b"hsqs")
        if i < 0:
            raise ValueError("no squashfs magic in image")
        return i

    def _rd(self, off, n):
        self.f.seek(self.off + off)
        return self.f.read(n)

    @staticmethod
    def _dec(b):
        return lzma.LZMADecompressor(format=lzma.FORMAT_AUTO).decompress(b)

    def _meta_block(self, abs_off):
        """Return (decompressed bytes, bytes consumed) for one metadata block."""
        if abs_off in self._meta:
            return self._meta[abs_off]
        hdr = struct.unpack("<H", self._rd(abs_off, 2))[0]
        size = hdr & 0x7FFF
        compressed = not (hdr & 0x8000)
        raw = self._rd(abs_off + 2, size)
        self._meta[abs_off] = (self._dec(raw) if compressed else raw, 2 + size)
        return self._meta[abs_off]

    def _read_meta(self, table_start, block_off, offset, nbytes):
        """Read nbytes from a metadata table starting at (block_off, offset)."""
        out = bytearray()
        bo, first = block_off, True
        while len(out) < nbytes:
            data, adv = self._meta_block(table_start + bo)
            if first:
                data, first = data[offset:], False
            out += data
            bo += adv
            if not adv:
                break
        return bytes(out[:nbytes])

    def _inode(self, ref):
        blk, off = (ref >> 16) & 0xFFFFFFFFFFFF, ref & 0xFFFF
        hdr = self._read_meta(self.inode_start, blk, off, 64)
        itype = struct.unpack_from("<H", hdr, 0)[0]
        return itype, hdr, blk, off

    def _frag_entry(self, idx):
        per = 8192 // 16
        loc = struct.unpack("<Q", self._rd(self.frag_start + 8 * (idx // per), 8))[0]
        data, _ = self._meta_block(loc)
        start, size, _unused = struct.unpack_from("<QII", data, (idx % per) * 16)
        return start, size

    def dir_entries(self, ref):
        itype, hdr, _blk, _off = self._inode(ref)
        if itype == 1:      # basic directory
            start_block, _nlink, fsize, doff, _parent = struct.unpack_from("<IIHHI", hdr, 16)
        elif itype == 8:    # extended directory
            _nlink, fsize, start_block, _parent, _ic, doff, _xattr = struct.unpack_from("<IIIIHHI", hdr, 16)
        else:
            return []
        raw = self._read_meta(self.dir_start, start_block, doff, fsize - 3)
        out, p = [], 0
        while p + 12 <= len(raw):
            count, start, _inum = struct.unpack_from("<IIi", raw, p)
            p += 12
            for _ in range(count + 1):
                if p + 8 > len(raw):
                    break
                eoff, _ioff, etype, size = struct.unpack_from("<HhHH", raw, p)
                p += 8
                name = raw[p:p + size + 1].decode("utf8", "replace")
                p += size + 1
                out.append((name, etype, (start << 16) | eoff))
        return out

    def file_data(self, ref):
        itype, hdr, blk, off = self._inode(ref)
        if itype == 2:      # basic file
            start_block, frag, foff, fsize = struct.unpack_from("<IIII", hdr, 16)
            bs_off = 32
        elif itype == 9:    # extended file
            start_block, fsize, _sparse, _nlink, frag, foff, _xattr = struct.unpack_from("<QQQIIII", hdr, 16)
            bs_off = 56
        else:
            return None
        nfull = fsize // self.bsize if frag != 0xFFFFFFFF else (fsize + self.bsize - 1) // self.bsize
        hdr2 = self._read_meta(self.inode_start, blk, off, bs_off + 4 * nfull)
        sizes = struct.unpack_from("<%dI" % nfull, hdr2, bs_off) if nfull else ()
        out, pos = bytearray(), start_block
        for s in sizes:
            n, compressed = s & 0xFFFFFF, not (s & 0x1000000)
            if n == 0:                       # sparse block
                out += b"\0" * self.bsize
                continue
            raw = self._rd(pos, n)
            out += self._dec(raw) if compressed else raw
            pos += n
        if frag != 0xFFFFFFFF and len(out) < fsize:
            fstart, fsz = self._frag_entry(frag)
            n, compressed = fsz & 0xFFFFFF, not (fsz & 0x1000000)
            raw = self._rd(fstart, n)
            fd = self._dec(raw) if compressed else raw
            out += fd[foff:foff + (fsize - len(out))]
        return bytes(out[:fsize])

    def walk(self, ref=None, path="", depth=0, maxdepth=16):
        ref = self.root_ref if ref is None else ref
        for name, etype, r in self.dir_entries(ref):
            if name in (".", ".."):
                continue
            p = path + "/" + name
            if etype in (1, 8):
                yield p, "d", r
                if depth < maxdepth:
                    yield from self.walk(r, p, depth + 1, maxdepth)
            else:
                yield p, "f", r

    def index(self):
        return {p: (t, r) for p, t, r in self.walk()}


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    cmd, image = argv[1], argv[2]
    fs = SquashFS(image)
    print("squashfs at 0x%x  v%d.%d  %d inodes  block %d" %
          (fs.off, fs.vmaj, fs.vmin, fs.inodes, fs.bsize), file=sys.stderr)
    idx = fs.index()
    if cmd == "list":
        pat = argv[3] if len(argv) > 3 else "*"
        for p in sorted(idx):
            if fnmatch.fnmatch(p, pat):
                print("%s%s" % (p, "/" if idx[p][0] == "d" else ""))
    elif cmd == "cat":
        for p in argv[3:]:
            sys.stdout.buffer.write(fs.file_data(idx[p][1]))
    elif cmd == "dump":
        dest = argv[3]
        for p in argv[4:]:
            data = fs.file_data(idx[p][1])
            out = os.path.join(dest, p.lstrip("/"))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "wb") as fh:
                fh.write(data)
            print("%8d  %s" % (len(data), out))
    elif cmd == "index":
        json.dump({k: [v[0], v[1]] for k, v in idx.items()}, sys.stdout)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
