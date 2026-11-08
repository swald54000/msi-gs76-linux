#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Le moteur d'affichage (sans PSR) est-il ce qui bloque
# le package en PC2 ?
#  1. Journalise pourquoi i915 refuse le PSR (débogage KMS pendant un changement de mode).
#  2. Mesure 20 s écran allumé, puis 20 s écran éteint (DPMS), puis le rallume.
# Suppose la dalle interne eDP-2 en 1920x1080 à 60/360 Hz (GS76) et une session Hyprland.
# Écrit ./diag-display.txt (dossier courant). Ne rien toucher (~1 min 30).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
utilisateur="$(utilisateur_cible)" || exit 1
uid_utilisateur="$(id -u "$utilisateur")"

OUT="$PWD/diag-display.txt"
DBG=/sys/kernel/debug
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
mountpoint -q $DBG || mount -t debugfs none $DBG
modprobe intel_pmc_core 2>/dev/null
I915=""
for d in "$DBG"/dri/*; do [[ -r $d/name ]] && grep -q i915 "$d"/name && I915=$d && break; done

# hyprctl dans la session Hyprland de l'utilisateur qui a lancé sudo.
hypr() {
  local sig
  sig=$(find "/run/user/$uid_utilisateur/hypr" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | head -1)
  runuser -u "$utilisateur" -- env XDG_RUNTIME_DIR="/run/user/$uid_utilisateur" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@"
}
mode() { hypr eval "hl.monitor({ output = \"eDP-2\", mode = \"1920x1080@$1\", position = \"0x0\", scale = 1 })"; }
dpms() { hypr dispatch "hl.dsp.dpms({ action = \"$1\", monitor = \"eDP-2\" })"; }
state() { echo "   -> écran : $(hypr monitors -j | python3 -I -c 'import json,sys; m=json.load(sys.stdin)[0]; print(f"{m[\"refreshRate\"]:.0f} Hz, allumé={m[\"dpmsStatus\"]}")')"; }
dbg_old=$(cat /sys/module/drm/parameters/debug)
restore() {
  echo "$dbg_old" >/sys/module/drm/parameters/debug
  dpms on >/dev/null
}
trap restore EXIT

measure() {
  local label=$1 a b e0 e1 d0 d1
  sleep 4
  a=$(cat $DBG/pmc_core/package_cstate_show); e0=$(<$RAPL); d0=$(grep -E 'DC5 -> DC6|DC3 -> DC5' "$I915"/i915_dmc_info | tr '\n' ' ')
  sleep 20
  b=$(cat $DBG/pmc_core/package_cstate_show); e1=$(<$RAPL); d1=$(grep -E 'DC5 -> DC6|DC3 -> DC5' "$I915"/i915_dmc_info | tr '\n' ' ')
  printf '%-14s %s W  ' "$label" "$(awk -v a="$e0" -v b="$e1" 'BEGIN{printf "%.2f",(b-a)/20e6}')"
  paste <(echo "$a") <(echo "$b") | awk -F'\t' '{split($1,x,":"); split($2,y,":"); v=(y[2]-x[2])/200000; if (v>=0.1) printf "%s %.1f%%  ", x[1], v}'
  echo; echo "               DMC avant : $d0"; echo "               DMC après : $d1"
}

echo "Ne touche plus à rien (~1 min 30). L'écran va s'éteindre 25 s puis se rallumer."
{
  echo "##### Pourquoi i915 refuse le PSR"
  since=$(date '+%Y-%m-%d %H:%M:%S')
  echo 0x04 >/sys/module/drm/parameters/debug          # KMS debug
  mode 60.04; sleep 2; state
  mode 360.04; sleep 2; state
  echo "$dbg_old" >/sys/module/drm/parameters/debug
  journalctl -k --no-pager -S "$since" | grep -iE 'psr|panel replay|sink' | sed 's/^.*kernel: //' | sort | uniq -c | sort -rn | head -25
  echo; echo "--- i915_edp_psr_status"; cat "$I915"/i915_edp_psr_status
  echo; echo "##### Écran allumé / éteint"
  sleep 3
  measure "Écran allumé"
  dpms off; sleep 1; state
  measure "Écran éteint"
} 2>&1 | tee "$OUT"

restore; trap - EXIT
chown "$utilisateur:" "$OUT"
echo "Écran rallumé. Terminé : $OUT"
