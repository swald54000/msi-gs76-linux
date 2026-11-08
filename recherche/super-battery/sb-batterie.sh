#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche. À lancer avec sudo, SUR BATTERIE (secteur débranché), PC au repos, sans rien toucher.
# Mesure la consommation réelle (courant × tension de la batterie) dans chaque état.
# Le module battery met normalement le courant en cache 5 min (cache_time=300000) :
# on le passe à 1 s le temps du test puis on le remet.
# Durée : 5 états × (60 s de stabilisation + MESURE s de mesure). MESURE=120 par défaut.
# Résultats écrits dans ./resultats-batterie.txt (dossier courant).
set -euo pipefail
export LC_ALL=C
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
proprio="$(utilisateur_cible 2>/dev/null || true)"
EC=/sys/devices/platform/msi-ec
B="$(batterie)" || { echec "aucune batterie trouvée"; exit 1; }
MESURE=${MESURE:-120}
[ "$(cat /sys/class/power_supply/ADP1/online)" = 0 ] || { echo "Débranche le secteur d'abord."; exit 1; }
cache_orig=$(cat /sys/module/battery/parameters/cache_time)
restore() {
  echo comfort > $EC/shift_mode || true; sleep 2; echo off > $EC/super_battery || true
  echo "$cache_orig" > /sys/module/battery/parameters/cache_time
  [ -n "$proprio" ] && chown "$proprio:" resultats-batterie.txt 2>/dev/null || true
  echo "Remis : shift_mode=$(cat $EC/shift_mode) super_battery=$(cat $EC/super_battery) cache_time=$(cat /sys/module/battery/parameters/cache_time)"
}
trap restore EXIT
echo 1000 > /sys/module/battery/parameters/cache_time

out=resultats-batterie.txt
echo "$(date) écran=$(hyprctl -j monitors 2>/dev/null | grep -o '"refreshRate": [0-9.]*' | head -1)" | tee $out
mesure() { # $1 nom
  echo "  $1 : stabilisation 60 s…"; sleep 60
  local s=0 n=0 t0 p
  t0=$(date +%s)
  while (( $(date +%s) - t0 < MESURE )); do
    p=$(awk -v i="$(cat "$B"/current_now)" -v u="$(cat "$B"/voltage_now)" 'BEGIN{if(i<0)i=-i; printf "%.0f", i*u/1e9}') # mW
    s=$((s+p)); n=$((n+1)); sleep 2
  done
  printf "%-18s shift=%-7s sb=%-3s  %5.2f W moyen (%d mesures)  MMIO PL1=%d W\n" "$1" \
    "$(cat $EC/shift_mode)" "$(cat $EC/super_battery)" "$(awk -v s=$s -v n=$n 'BEGIN{print s/n/1000}')" $n \
    $(( $(cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw)/1000000 )) | tee -a $out
}
echo comfort > $EC/shift_mode; echo off > $EC/super_battery; mesure 1-confort
echo eco     > $EC/shift_mode;                               mesure 2-eco-auto
echo off     > $EC/super_battery;                            mesure 3-eco-sb-off
echo on      > $EC/super_battery;                            mesure 4-eco-sb-on
echo comfort > $EC/shift_mode; echo off > $EC/super_battery; mesure 5-confort-retour
