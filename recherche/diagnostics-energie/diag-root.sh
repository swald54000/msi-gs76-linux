#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root) : diagnostic matériel du GS76 (lecture seule, ~40 s).
# Écrit ./diag-root.txt (dossier courant). Laisser le portable au repos pendant la mesure.
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root

OUT="$PWD/diag-root.txt"
proprio="$(utilisateur_cible 2>/dev/null || true)"
BAT="$(batterie)" || { echec "aucune batterie trouvée"; exit 1; }
DBG=/sys/kernel/debug
exec > >(tee "$OUT") 2>&1

echo "##### 1. Lecture batterie (_BST), cache désactivé"
P=/sys/module/battery/parameters/cache_time
old=$(<"$P"); echo 0 >"$P"
TIMEFORMAT='%3R s'
for _ in 1 2 3 4 5; do time cat "$BAT"/voltage_now >/dev/null; done
echo "$old" >"$P"

echo; echo "##### 2. ASPM réglé par le BIOS (LnkCap / LnkCtl / L1SS)"
for d in $(lspci -D | awk '{print $1}'); do
  info=$(lspci -vvv -s "$d" 2>/dev/null | grep -E 'LnkCap:|LnkCtl:|L1SubCap:|L1SubCtl1:' | sed 's/^\s*/    /')
  [[ -n $info ]] && { echo "$d $(lspci -s "$d" | cut -d' ' -f2- | cut -c1-70)"; echo "$info"; }
done

echo; echo "##### 3. Requêtes EC (_Qxx) et transactions pendant 15 s"
mountpoint -q $DBG || mount -t debugfs none $DBG
g0=$(awk '{print $1}' /sys/firmware/acpi/interrupts/gpe6E)
echo 'file drivers/acpi/ec.c +p' >$DBG/dynamic_debug/control
since=$(date '+%Y-%m-%d %H:%M:%S')
sleep 15
echo 'file drivers/acpi/ec.c -p' >$DBG/dynamic_debug/control
g1=$(awk '{print $1}' /sys/firmware/acpi/interrupts/gpe6E)
echo "GPE 0x6E : $((g1 - g0)) en 15 s"
log=$(journalctl -k --no-pager -S "$since")
echo "Requêtes par code :"
grep -oE 'Query\(0x[0-9a-f]{2}\) started' <<<"$log" | sort | uniq -c | sort -rn
echo "Transactions EC : $(grep -cE 'Command\((RD_EC|WR_EC)\) started' <<<"$log")"
grep -oE 'Command\((RD_EC|WR_EC|QR_EC)\) started' <<<"$log" | sort | uniq -c

echo; echo "##### 4. États C du package au repos (pmc_core), 10 s"
modprobe intel_pmc_core 2>/dev/null
if [[ -r $DBG/pmc_core/package_cstate_show ]]; then
  a=$(cat $DBG/pmc_core/package_cstate_show); sleep 10; b=$(cat $DBG/pmc_core/package_cstate_show)
  paste <(echo "$a") <(echo "$b") | awk -F'\t' '{split($1,x,":"); split($2,y,":"); printf "%-12s %8.1f ms\n", x[1], (y[2]-x[2])/1000}'
  echo; echo "--- ltr_show (périphériques qui empêchent les états profonds)"
  cat $DBG/pmc_core/ltr_show
  echo; echo "--- slp_s0_residency_usec : $(cat $DBG/pmc_core/slp_s0_residency_usec 2>/dev/null)"
  echo "--- substate_requirements"; cat $DBG/pmc_core/substate_requirements 2>/dev/null | head -60
else
  echo "pmc_core indisponible"
fi

echo; echo "##### 5. Ports PCIe : D3cold autorisé / état"
for d in /sys/bus/pci/devices/*; do
  printf '%s %-7s d3cold_allowed=%s runtime=%s\n' "$(basename "$d")" "$(cat "$d"/power_state 2>/dev/null)" \
    "$(cat "$d"/d3cold_allowed 2>/dev/null)" "$(cat "$d"/power/runtime_status 2>/dev/null)"
done

[ -n "$proprio" ] && chown "$proprio:" "$OUT"
echo; echo "Terminé : $OUT"
