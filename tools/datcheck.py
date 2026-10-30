#!/usr/bin/env python3
"""Check MAME romset zips against the mame2003-plus DAT the cabinet ships.

    tools/datcheck.py [--dat PATH] [--list] romset.zip [romset.zip ...]
    tools/datcheck.py --dat PATH --info gridlee

The DAT is `/usr/share/libretro/system/mame2003-plus/mame2003-plus.xml` on the
cabinet (20 MB). Pull it once; the default path below is the git-ignored local
copy. For each zip the tool reports, per ROM the core expects: present with the
right CRC, present with the wrong CRC (wrong MAME version, the usual failure),
or missing. ROMs a clone inherits from its parent (`merge=`) are looked for in
the clone zip first, then in a sibling `<parent>.zip` next to it, which is how a
split set is laid out. Exit status is 0 only when every zip is fully loadable.
No network, no cabinet access: stdlib only.
"""
import argparse
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

DEFAULT_DAT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "local", "cabinet-dat", "mame2003-plus.xml")


def load_dat(path):
    games = {}
    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag != "game":
            continue
        roms = []
        for r in el.findall("rom"):
            crc = r.get("crc")
            if crc is None:          # nodump entries have no crc; the core does not need them
                continue
            roms.append({"name": r.get("name"), "size": int(r.get("size") or 0),
                         "crc": crc.lower(), "merge": r.get("merge")})
        games[el.get("name")] = {
            "description": el.findtext("description", ""),
            "year": el.findtext("year", ""),
            "manufacturer": el.findtext("manufacturer", ""),
            "cloneof": el.get("cloneof"), "romof": el.get("romof"),
            "roms": roms,
            "samples": [s.get("name") for s in el.findall("sample")],
            "runnable": el.get("runnable", "yes") != "no",
        }
        el.clear()
    return games


def zip_crcs(path):
    """name -> (crc hex, size) for every member; names compared case-insensitively."""
    out = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            out[info.filename.lower()] = ("%08x" % info.CRC, info.file_size)
    return out


def check_zip(path, games):
    setname = os.path.splitext(os.path.basename(path))[0].lower()
    game = games.get(setname)
    if game is None:
        return False, [f"{setname}: not in the DAT (not a MAME 0.78 / mame2003-plus set name)"]
    lines = [f"{setname}: {game['description']} ({game['manufacturer']}, {game['year']})"]
    if not game["runnable"]:
        lines.append("  BIOS/device set, not a game")
    if game["cloneof"]:
        lines.append(f"  clone of {game['cloneof']}")
    here = zip_crcs(path)
    parent = {}
    if game["romof"]:
        ppath = os.path.join(os.path.dirname(path), game["romof"] + ".zip")
        if os.path.exists(ppath):
            parent = zip_crcs(ppath)
            lines.append(f"  parent zip found: {os.path.basename(ppath)}")
    ok = bad = missing = 0
    for rom in game["roms"]:
        got = here.get(rom["name"].lower())
        where = "zip"
        if got is None and rom["merge"]:
            got = parent.get(rom["merge"].lower()) or parent.get(rom["name"].lower())
            where = "parent"
        if got is None:
            # the same bytes may sit in the zip under another name
            alt = [n for n, (c, s) in here.items() if c == rom["crc"] and s == rom["size"]]
            if alt:
                got = here[alt[0]]; where = f"zip as {alt[0]}"
        if got is None:
            missing += 1
            lines.append(f"  MISSING  {rom['name']}  crc {rom['crc']}  {rom['size']} bytes"
                         + (f"  (parent {game['romof']}.zip not found)" if rom["merge"] and not parent else ""))
        elif got[0] != rom["crc"]:
            bad += 1
            lines.append(f"  BAD CRC  {rom['name']}  want {rom['crc']} have {got[0]}  (wrong MAME version?)")
        else:
            ok += 1
    extra = sorted(set(here) - {r["name"].lower() for r in game["roms"]})
    if extra:
        lines.append(f"  {len(extra)} file(s) the core does not ask for: " + ", ".join(extra[:6])
                     + (" ..." if len(extra) > 6 else ""))
    if game["samples"]:
        lines.append(f"  optional samples: {setname}.zip in system/mame2003-plus/samples/ ({len(game['samples'])} files; plays without)")
    verdict = "LOADABLE" if bad == 0 and missing == 0 else "WILL NOT LOAD"
    lines.append(f"  {verdict}: {ok} ok, {bad} bad crc, {missing} missing of {len(game['roms'])}")
    return bad == 0 and missing == 0, lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dat", default=DEFAULT_DAT)
    ap.add_argument("--info", metavar="SET", help="print what the DAT says about SET and exit")
    ap.add_argument("--list", action="store_true", help="only print set name + description per zip")
    ap.add_argument("zips", nargs="*")
    a = ap.parse_args()
    if not os.path.exists(a.dat):
        sys.exit(f"DAT not found at {a.dat}; pull it from the cabinet first")
    games = load_dat(a.dat)
    if a.info:
        g = games.get(a.info.lower())
        if g is None:
            sys.exit(f"{a.info}: not in the DAT")
        print(f"{a.info}: {g['description']} ({g['manufacturer']}, {g['year']})"
              + (f", clone of {g['cloneof']}" if g["cloneof"] else ""))
        for r in g["roms"]:
            print(f"  {r['name']:<20} {r['size']:>8}  {r['crc']}" + (f"  merge={r['merge']}" if r["merge"] else ""))
        if g["samples"]:
            print(f"  samples: {', '.join(g['samples'])}")
        return
    if not a.zips:
        ap.error("give at least one romset zip, or --info SET")
    all_ok = True
    for z in a.zips:
        if not zipfile.is_zipfile(z):
            print(f"{z}: not a zip file"); all_ok = False; continue
        ok, lines = check_zip(z, games)
        all_ok &= ok
        print("\n".join(lines if not a.list else lines[:1]))
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
