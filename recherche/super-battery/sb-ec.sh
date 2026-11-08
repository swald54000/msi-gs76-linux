#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche. À lancer avec sudo, sur secteur. Teste super_battery INDÉPENDAMMENT de shift_mode.
# EC en LECTURE SEULE pour les dumps (ec_sys write_support=0) ; les seules écritures
# passent par les attributs du pilote msi-ec (shift_mode, super_battery), comme MSI Center.
# Pour chaque état : dump des 256 octets de l'EC + limites de puissance MMIO (celles que l'EC impose).
# Remet toujours confort + super_battery off à la fin (trap).
# Dumps dans ./dumps/ et résultats dans ./resultats-ec.txt (dossier courant).
set -euo pipefail
export LC_ALL=C
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
proprio="$(utilisateur_cible 2>/dev/null || true)"
EC=/sys/devices/platform/msi-ec
MMIO=/sys/class/powercap/intel-rapl-mmio:0
mkdir -p dumps
modprobe ec_sys write_support=0
[ "$(cat /sys/module/ec_sys/parameters/write_support)" = N ] || { echo "ec_sys est en écriture, abandon"; exit 1; }
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
IO=/sys/kernel/debug/ec/ec0/io

restore() {
  echo comfort > $EC/shift_mode || true
  sleep 2
  echo off > $EC/super_battery || true
  [ -n "$proprio" ] && chown -R "$proprio:" dumps resultats-ec.txt 2>/dev/null || true
  modprobe -r ec_sys 2>/dev/null || true
  echo "Remis : shift_mode=$(cat $EC/shift_mode) super_battery=$(cat $EC/super_battery)"
}
trap restore EXIT

ts=$(date +%Y%m%d-%H%M%S)
out=resultats-ec.txt
: > $out
state() { # $1 nom
  sleep 4
  local f="dumps/$ts-$1.bin"
  cp $IO "$f"
  printf "%-22s shift=%-7s sb=%-3s 0xD2=%s 0xEB=%s  MMIO PL1=%3d W PL2=%3d W\n" "$1" \
    "$(cat $EC/shift_mode)" "$(cat $EC/super_battery)" \
    "$(xxd -s 0xd2 -l1 -p "$f")" "$(xxd -s 0xeb -l1 -p "$f")" \
    $(( $(cat $MMIO/constraint_0_power_limit_uw)/1000000 )) \
    $(( $(cat $MMIO/constraint_1_power_limit_uw)/1000000 )) | tee -a $out
}

echo comfort > $EC/shift_mode; echo off > $EC/super_battery; state 1-confort
echo eco     > $EC/shift_mode;                               state 2-eco-auto
echo off     > $EC/super_battery;                            state 3-eco-sb-off
echo on      > $EC/super_battery;                            state 4-eco-sb-on
echo comfort > $EC/shift_mode;                               state 5-confort-apres-eco
echo on      > $EC/super_battery;                            state 6-confort-sb-on
echo turbo   > $EC/shift_mode;                               state 7-turbo-apres-sb
echo off     > $EC/super_battery;                            state 8-turbo-sb-off

echo; echo "Octets qui changent par rapport à 1-confort (hors 0xC0-0xCF = vitesses/tachy) :"
for f in dumps/"$ts"-*.bin; do
  n=$(basename "$f" .bin); n=${n#"$ts"-}
  [ "$n" = 1-confort ] && continue
  d=$(cmp -l dumps/"$ts"-1-confort.bin "$f" 2>/dev/null | awk '{a=$1-1; if (a<0xC0||a>0xCF) printf "0x%02X:%02x→%02x ", a, strtonum("0"$2), strtonum("0"$3)}')
  echo "  $n : ${d:-aucun}" | tee -a $out
done
