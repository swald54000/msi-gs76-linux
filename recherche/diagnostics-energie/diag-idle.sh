#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Consommation au repos : états C du package et puissance
# du package CPU à 360 Hz contre 60 Hz.
# Passe la dalle interne (eDP-2) à 60 Hz pendant ~20 s, puis la remet à 360 Hz.
# Écrit ./diag-idle.txt (dossier courant). Ne pas toucher au portable pendant la mesure (~1 min).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
utilisateur="$(utilisateur_cible)" || exit 1
uid_utilisateur="$(id -u "$utilisateur")"

OUT="$PWD/diag-idle.txt"
DBG=/sys/kernel/debug
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
exec > >(tee "$OUT") 2>&1
mountpoint -q $DBG || mount -t debugfs none $DBG
modprobe intel_pmc_core 2>/dev/null

# hyprctl dans la session Hyprland de l'utilisateur qui a lancé sudo.
hypr() {
  local sig
  sig=$(find "/run/user/$uid_utilisateur/hypr" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | head -1)
  runuser -u "$utilisateur" -- env XDG_RUNTIME_DIR="/run/user/$uid_utilisateur" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@"
}

I915=""
for d in "$DBG"/dri/*; do [[ -r $d/name ]] && grep -q i915 "$d"/name && I915=$d && break; done

measure() {
  local label=$1 a b e0 e1
  sleep 4
  a=$(cat $DBG/pmc_core/package_cstate_show); e0=$(<$RAPL)
  sleep 15
  b=$(cat $DBG/pmc_core/package_cstate_show); e1=$(<$RAPL)
  echo "===== $label"
  awk -v e0="$e0" -v e1="$e1" 'BEGIN{printf "Puissance package CPU : %.2f W\n", (e1-e0)/15e6}'
  paste <(echo "$a") <(echo "$b") | awk -F'\t' '{split($1,x,":"); split($2,y,":"); printf "  %-12s %5.1f %%\n", x[1], (y[2]-x[2])/150000}'
}

echo "##### Affichage"
hypr monitors | grep -E 'Monitor|@'
if [[ -n $I915 ]]; then
  echo "--- PSR"; cat "$I915"/i915_edp_psr_status 2>/dev/null | head -12
  echo "--- DMC"; cat "$I915"/i915_dmc_info 2>/dev/null | head -20
fi
echo

measure "360 Hz"
hypr keyword monitor eDP-2,1920x1080@60.04,0x0,1 >/dev/null
measure "60 Hz"
if [[ -n $I915 ]]; then echo "--- PSR à 60 Hz"; cat "$I915"/i915_edp_psr_status 2>/dev/null | head -6; fi
hypr keyword monitor eDP-2,1920x1080@360.04,0x0,1 >/dev/null
echo; echo "Écran remis à 360 Hz."

chown "$utilisateur:" "$OUT"
echo "Terminé : $OUT"
