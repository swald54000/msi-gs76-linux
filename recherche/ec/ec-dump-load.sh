#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche, à lancer avec sudo depuis le dossier où ranger les dumps.
# LECTURE SEULE de l'EC. Met le ventilateur en mode auto, charge tous les cœurs
# 60 s, copie l'EC dans ./dumps/ toutes les 10 s, puis remet le mode d'origine.
# But : valider l'adresse des tours/minute (0xC8/0xCA) avec le ventilateur en marche.
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
orig=$(cat $EC/fan_mode); ts=$(date +%Y%m%d-%H%M%S)
trap 'echo "$orig" > $EC/fan_mode; modprobe -r ec_sys 2>/dev/null || true; [ -n "$proprio" ] && chown -R "$proprio:" dumps' EXIT
echo auto > $EC/fan_mode
for _ in $(seq "$(nproc)"); do timeout 60 sh -c 'while :; do :; done' & done
for t in 10 20 30 40 50 60 70 80; do sleep 10; cp $IO "dumps/$ts-charge-${t}s.bin"; echo "t=${t}s fan=$(cat $EC/cpu/realtime_fan_speed)%"; done
wait
echo "OK, mode remis à $orig"
