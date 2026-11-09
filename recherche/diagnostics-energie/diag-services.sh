#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Arrêter les services les plus bavards laisse-t-il le
# package descendre sous PC2 ? Étapes cumulatives de 20 s : référence, - un service
# utilisateur (optionnel : SERVICE_UTILISATEUR=nom.service), - nvidia-powerd, - thermald. Tous relancés à la fin.
# Attend d'abord 20 s (ne rien toucher). Écrit ./diag-services.txt (dossier courant).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
utilisateur="$(utilisateur_cible)" || exit 1

OUT="$PWD/diag-services.txt"
DBG=/sys/kernel/debug
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
mountpoint -q $DBG || mount -t debugfs none $DBG
modprobe intel_pmc_core 2>/dev/null

SERVICE="${SERVICE_UTILISATEUR:-}"
usvc() { systemctl --user -M "$utilisateur@" "$@"; }
restore() {
  [ -n "$SERVICE" ] && usvc start "$SERVICE" 2>/dev/null
  systemctl start nvidia-powerd.service thermald.service 2>/dev/null
}
trap restore EXIT

measure() {
  local label=$1 a b e0 e1 i0 i1
  sleep 5
  a=$(cat $DBG/pmc_core/package_cstate_show); e0=$(<$RAPL)
  i0=$(awk '/LOC:/{s=0;for(i=2;i<=NF;i++)if($i~/^[0-9]+$/)s+=$i;print s}' /proc/interrupts)
  sleep 20
  b=$(cat $DBG/pmc_core/package_cstate_show); e1=$(<$RAPL)
  i1=$(awk '/LOC:/{s=0;for(i=2;i<=NF;i++)if($i~/^[0-9]+$/)s+=$i;print s}' /proc/interrupts)
  printf '%-22s %s W  timer %4d/s  ' "$label" "$(awk -v a="$e0" -v b="$e1" 'BEGIN{printf "%.2f",(b-a)/20e6}')" $(( (i1-i0)/20 ))
  paste <(echo "$a") <(echo "$b") | awk -F'\t' '{split($1,x,":"); split($2,y,":"); v=(y[2]-x[2])/200000; if (v>=0.1) printf "%s %.1f%%  ", x[1], v}'
  echo
}

echo "Ne touche plus à rien : début dans 20 s, durée ~2 min."
sleep 20
{
  measure "Référence"
  if [ -n "$SERVICE" ]; then usvc stop "$SERVICE"; measure "- service utilisateur"; fi
  systemctl stop nvidia-powerd.service;   measure "- nvidia-powerd"
  systemctl stop thermald.service;        measure "- thermald"
} | tee "$OUT"

restore; trap - EXIT
etat_service=""
[ -n "$SERVICE" ] && etat_service="service-utilisateur=$(usvc is-active "$SERVICE") "
echo "Services relancés : ${etat_service}nvidia-powerd=$(systemctl is-active nvidia-powerd) thermald=$(systemctl is-active thermald)" | tee -a "$OUT"
chown "$utilisateur:" "$OUT"
