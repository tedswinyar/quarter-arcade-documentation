#!/usr/bin/env python3
"""Write a RetroArch game override for every vertical romset on the drive.

    tools/retroarch/make-overrides.py [--dat PATH] [--out-dir DIR] ROMS_DIR

The cabinet draws every game inside the window its bezel leaves visible, a
custom viewport of 814x600 at x=115 on the 1024x600 panel. That box is 4:3 and
a vertical (3:4) game forced into it is squeezed to ~55 % of its proper
height. This tool reads the DAT's screen orientation for each zip in ROMS_DIR
and writes `<setname>.cfg` for the vertical ones, each holding a 3:4 viewport
centred in the same opening with the same pixel aspect (458x600 at x=293).
Horizontal games get no file and keep the vendor viewport. Copy the output
directory to `~/.config/retroarch/config/MAME 2003-Plus/` on the cabinet
(with `rgui_config_directory` pointed at `~/.config/retroarch/config`).
RetroArch applies overrides when content loads. Stdlib only.
"""
import argparse
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DAT = os.path.normpath(os.path.join(HERE, "..", "..", "local", "cabinet-dat", "mame2003-plus.xml"))

# Bezel opening measured on the TMNT cabinet (docs/01, docs/11).
OPEN_X, OPEN_W, OPEN_H = 115, 814, 600
# 3:4 image at the opening's pixel aspect (the opening shows 4:3 content).
VERT_W = round(OPEN_H * 0.75 * (OPEN_W / OPEN_H) / (4 / 3))
VERT_X = OPEN_X + (OPEN_W - VERT_W) // 2

TEMPLATE = (
    'aspect_ratio_index = "23"\n'
    f'custom_viewport_width = "{VERT_W}"\n'
    f'custom_viewport_height = "{OPEN_H}"\n'
    f'custom_viewport_x = "{VERT_X}"\n'
    'custom_viewport_y = "0"\n'
)


def orientations(dat_path, wanted):
    out = {}
    for _, el in ET.iterparse(dat_path, events=("end",)):
        if el.tag == "game":
            if el.get("name") in wanted:
                v = el.find("video")
                out[el.get("name")] = v.get("orientation") if v is not None else None
            el.clear()
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("roms_dir")
    ap.add_argument("--dat", default=DEFAULT_DAT)
    ap.add_argument("--out-dir", default="MAME 2003-Plus")
    a = ap.parse_args()
    if not os.path.exists(a.dat):
        sys.exit(f"DAT not found at {a.dat}; pull it from the cabinet first")
    sets = sorted(os.path.splitext(f)[0].lower() for f in os.listdir(a.roms_dir)
                  if f.lower().endswith(".zip") and not f.startswith("._"))
    orient = orientations(a.dat, set(sets))
    os.makedirs(a.out_dir, exist_ok=True)
    n = 0
    for s in sets:
        o = orient.get(s)
        if o is None:
            print(f"skipped (not in DAT): {s}", file=sys.stderr)
        elif o == "vertical":
            with open(os.path.join(a.out_dir, f"{s}.cfg"), "w") as f:
                f.write(TEMPLATE)
            n += 1
    print(f"{n} vertical set(s) -> {a.out_dir}/  (viewport {VERT_W}x{OPEN_H} @ x={VERT_X})")


if __name__ == "__main__":
    main()
