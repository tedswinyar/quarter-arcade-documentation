#!/usr/bin/env python3
"""Print every key event from the cabinet's input devices, labelled.

Runs ON the cabinet (python3 + evdev are in the stock rootfs):

    adb push tools/btnmap.py /tmp/
    adb shell python3 /tmp/btnmap.py

Then press each physical control one at a time; each press prints one line:

    event0  Dashine Arcade 1293 Joystick  BTN_A (304)  DOWN

Read-only; ctrl-c (or adb disconnect) to stop.
"""
import select
import time

from evdev import InputDevice, ecodes, list_devices

devs = {}
for path in list_devices():
    d = InputDevice(path)
    devs[d.fd] = d
    print("listening: %-8s %s" % (path.split("/")[-1], d.name), flush=True)

names = {}
for code, name in ecodes.bytype[ecodes.EV_KEY].items():
    names[code] = name if isinstance(name, str) else name[0]

while True:
    r, _, _ = select.select(list(devs), [], [])
    now = time.time()
    for fd in r:
        for ev in devs[fd].read():
            if ev.type == ecodes.EV_KEY and ev.value in (0, 1):
                print("%.1f %-7s %-30s %s (%d) %s" % (
                    now, devs[fd].path.split("/")[-1], devs[fd].name,
                    names.get(ev.code, "?"), ev.code,
                    "DOWN" if ev.value else "UP"), flush=True)
            elif ev.type == ecodes.EV_ABS:
                print("%.1f %-7s %-30s ABS code=%d value=%d" % (
                    now, devs[fd].path.split("/")[-1], devs[fd].name,
                    ev.code, ev.value), flush=True)
