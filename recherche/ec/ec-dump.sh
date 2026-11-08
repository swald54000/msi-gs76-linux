#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche, à lancer avec sudo depuis le dossier où ranger les dumps.
# LECTURE SEULE de l'EC : charge ec_sys SANS write_support et copie ses 256 octets
# dans ./dumps/, une fois par mode de ventilation (auto, silent, advanced), puis
# remet le mode d'origine. Les seules écritures passent par l'attribut fan_mode du
# pilote msi-ec.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
proprio="$(utilisateur_cible 2>/dev/null || true)"
EC=/sys/devices/platform/msi-ec
mkdir -p dumps
modprobe ec_sys write_support=0
[ "$(cat /sys/module/ec_sys/parameters/write_support)" = N ] || { echo "ec_sys est en écriture, abandon"; exit 1; }
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
IO=/sys/kernel/debug/ec/ec0/io
orig=$(cat $EC/fan_mode)
ts=$(date +%Y%m%d-%H%M%S)
for m in auto silent advanced; do
  echo "$m" > $EC/fan_mode; sleep 2
  cp $IO "dumps/$ts-$m.bin"
done
echo "$orig" > $EC/fan_mode
cp $IO "dumps/$ts-retour-$orig.bin"
[ -n "$proprio" ] && chown -R "$proprio:" dumps
modprobe -r ec_sys
echo "OK : $(find dumps -name "$ts-*" | wc -l) dumps dans $PWD/dumps, mode remis à $orig"
