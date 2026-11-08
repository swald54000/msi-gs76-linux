#!/usr/bin/env bash
# Outil de recherche, sans sudo, après le redémarrage : le quirk est-il actif, et le
# contrôleur RVB du clavier (SteelSeries KLC 1038:113a) s'est-il énuméré proprement ?
grep -o 'usbcore.quirks=[^ ]*' /proc/cmdline || echo "quirk ABSENT de /proc/cmdline"
d=""
for u in /sys/bus/usb/devices/*; do
  [ "$(cat "$u/idVendor" 2>/dev/null):$(cat "$u/idProduct" 2>/dev/null)" = 1038:113a ] && { d=$u; break; }
done
if [ -z "$d" ]; then
  echo "contrôleur 1038:113a introuvable sur le bus USB"
  exit 1
fi
port=$(basename "$d")
echo "périphérique : $port"
echo "quirks sysfs : $(cat "$d/quirks" 2>/dev/null)  (0x400 attendu = NO_LPM)"
echo "usb2_hardware_lpm : $(cat "$d/power/usb2_hardware_lpm" 2>/dev/null || echo 'absent (normal si NO_LPM)')"
echo "erreurs -71 ce boot : $(journalctl -b -k --no-pager | grep -cE "$port.*(error -71|not accepting)")"
