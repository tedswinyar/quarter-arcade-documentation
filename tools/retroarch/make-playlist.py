#!/usr/bin/env python3
"""Build a RetroArch playlist for the romsets on the cabinet's USB drive.

    tools/retroarch/make-playlist.py [--dat PATH] [--prefix /media/usb0/roms]
                                     [--out "Arcade (USB).lpl"] ROMS_DIR

ROMS_DIR is the drive's `roms/` folder (mounted on a PC) or any folder holding
the same zip names. Titles come from the mame2003-plus DAT (pull it from the
cabinet once; default path is the git-ignored local copy), with the trailing
"(Manufacturer, Year)" dropped and the set name appended in brackets so the
menu shows "Gridlee  [gridlee]". Sets the DAT does not know are skipped with
a note, because the core would not load them anyway; run datcheck.py first for
the full verdict. Paths in the playlist are where the cabinet mounts the drive,
not where the folder is on the PC. Stdlib only, no cabinet access.
"""
import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DAT = os.path.join(HERE, "..", "..", "local", "cabinet-dat", "mame2003-plus.xml")
CORE = "/usr/lib/libretro/mame2003plus_libretro.so"
CORE_NAME = "MAME 2003-Plus"


def titles(dat_path, wanted):
    out = {}
    for _, el in ET.iterparse(dat_path, events=("end",)):
        if el.tag == "game":
            if el.get("name") in wanted:
                out[el.get("name")] = el.findtext("description", el.get("name"))
            el.clear()
    return out


def label_for(setname, desc):
    label = re.sub(r"\s*\([^()]*\)\s*$", "", desc)          # drop "(Manufacturer, Year)"
    label = re.sub(r"\s*\((?:US|USA|World|Japan|Europe|rev [^)]*|set \d|revision \d|bootleg|hack|"
                   r"[A-Za-z ]*license)\)", "", label).strip() or desc
    return f"{label}  [{setname}]"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("roms_dir")
    ap.add_argument("--dat", default=os.path.normpath(DEFAULT_DAT))
    ap.add_argument("--prefix", default="/media/usb0/roms", help="where the cabinet sees the folder")
    ap.add_argument("--out", default="Arcade (USB).lpl")
    a = ap.parse_args()
    if not os.path.exists(a.dat):
        sys.exit(f"DAT not found at {a.dat}; pull it from the cabinet first")
    sets = sorted(os.path.splitext(f)[0].lower() for f in os.listdir(a.roms_dir)
                  if f.lower().endswith(".zip") and not f.startswith("._"))
    if not sets:
        sys.exit(f"no zips in {a.roms_dir}")
    known = titles(a.dat, set(sets))
    items = []
    for s in sets:
        if s not in known:
            print(f"skipped (not in DAT): {s}", file=sys.stderr)
            continue
        items.append({"path": f"{a.prefix.rstrip('/')}/{s}.zip", "label": label_for(s, known[s]),
                      "core_path": CORE, "core_name": CORE_NAME, "crc32": "",
                      "db_name": os.path.basename(a.out)})
    playlist = {"version": "1.4", "default_core_path": CORE, "default_core_name": CORE_NAME,
                "label_display_mode": 0, "right_thumbnail_mode": 0, "left_thumbnail_mode": 0,
                "sort_mode": 0, "items": items}
    with open(a.out, "w") as f:
        json.dump(playlist, f, indent=2)
        f.write("\n")
    print(f"{len(items)} entries -> {a.out}")


if __name__ == "__main__":
    main()
