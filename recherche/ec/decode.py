#!/usr/bin/env python3
"""Décode un dump EC du GS76 (firmware 17M1EMS1.113). Modèle de courbe : 6 seuils de montée,
7 vitesses, hystérésis = écart montée − descente (YAMDCC GS76, MControlCenter, isw, PR #143).
Le nombre de températures par courbe (6 ou 7) reste une question ouverte : voir ../README.fr.md.

Usage : python3 -I decode.py dumps/*.bin   (lecture seule, aucun privilège requis)"""
import sys
for path in sys.argv[1:]:
    b = open(path, 'rb').read()
    w = lambda a: b[a] << 8 | b[a + 1]
    rpm = lambda a: 480000 // w(a) if w(a) else 0
    def courbe(t, s, h):
        parts = [f"<{b[t]}°C:{b[s]}%"] + [f"{b[t+i]}°C(↓{b[t+i]-b[h+i]}):{b[s+i+1]}%" for i in range(6)]
        return " ".join(parts)
    print(f"== {path}")
    print(f"  CPU {b[0x68]} °C, {b[0x71]} %, {rpm(0xC8)} tr/min | GPU {b[0x80]} °C, {b[0x89]} %, "
          f"{rpm(0xCA)} tr/min | auxiliaire {rpm(0xCC)} tr/min")
    print("  courbe CPU : " + courbe(0x6A, 0x72, 0x7A))
    print("  courbe GPU : " + courbe(0x82, 0x8A, 0x92))
    print(f"  fan_mode 0x{b[0xD4]:02x}  shift 0x{b[0xD2]:02x}  cooler_boost {'on' if b[0x98] & 0x80 else 'off'}  "
          f"charge max {b[0xD7] & 0x7F} %  super_battery 0x{b[0xEB] & 0x0F:x}  usb_share 0x{b[0xBF]:02x}")
