#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Le PSR peut-il fonctionner sur cette dalle, et à quelle
# fréquence ? Force le PSR1 dans i915 (debugfs, au plus jusqu'au redémarrage),
# journalise les décisions PSR d'i915 et mesure la consommation au repos à 360 Hz
# et à 60 Hz. Tout est restauré à la fin.
# L'écran clignote aux changements de mode. Si l'image se fige ou se dégrade, c'est
# le PSR : attendre la fin (ou Ctrl-C), tout redevient normal.
# Écrit ./diag-psr.txt (dossier courant). Ne rien toucher (~2 min).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
utilisateur="$(utilisateur_cible)" || exit 1
uid_utilisateur="$(id -u "$utilisateur")"

OUT="$PWD/diag-psr.txt"
DBG=/sys/kernel/debug
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
mountpoint -q $DBG || mount -t debugfs none $DBG
modprobe intel_pmc_core 2>/dev/null
I915=""
for d in "$DBG"/dri/*; do [[ -r $d/name ]] && grep -q i915 "$d"/name && I915=$d && break; done
PSRDBG="$I915"/i915_edp_psr_debug

# hyprctl dans la session Hyprland de l'utilisateur qui a lancé sudo.
hypr() {
  local sig
  sig=$(find "/run/user/$uid_utilisateur/hypr" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | head -1)
  runuser -u "$utilisateur" -- env XDG_RUNTIME_DIR="/run/user/$uid_utilisateur" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@"
}
mode() { hypr eval "hl.monitor({ output = \"eDP-2\", mode = \"1920x1080@$1\", position = \"0x0\", scale = 1 })" >/dev/null; sleep 3; }
state() { echo "   écran : $(hypr monitors | grep -oE '[0-9]+x[0-9]+@[0-9.]+' | head -1)  |  $(grep -E '^PSR mode|Source PSR status' "$I915"/i915_edp_psr_status | tr '\n' ' ')"; }

dbg_old=$(cat /sys/module/drm/parameters/debug)
psr_old=$(cat "$PSRDBG")
restore() {
  echo "$dbg_old" >/sys/module/drm/parameters/debug
  echo "$psr_old" >"$PSRDBG"
  mode 360.04
}
trap restore EXIT

measure() {
  local label=$1 a b e0 e1 d0 d1
  sleep 4
  a=$(cat $DBG/pmc_core/package_cstate_show); e0=$(<$RAPL); d0=$(awk '/DC3 -> DC5/{print $NF}' "$I915"/i915_dmc_info)
  sleep 20
  b=$(cat $DBG/pmc_core/package_cstate_show); e1=$(<$RAPL); d1=$(awk '/DC3 -> DC5/{print $NF}' "$I915"/i915_dmc_info)
  printf '%-26s %s W  DC5 +%s  ' "$label" "$(awk -v a="$e0" -v b="$e1" 'BEGIN{printf "%.2f",(b-a)/20e6}')" $((d1 - d0))
  paste <(echo "$a") <(echo "$b") | awk -F'\t' '{split($1,x,":"); split($2,y,":"); v=(y[2]-x[2])/200000; if (v>=0.1) printf "%s %.1f%%  ", x[1], v}'
  echo
}

echo "Ne touche plus à rien (~2 min). L'écran va clignoter plusieurs fois."
{
  echo "##### Mesures sans PSR (réglage MSI)"
  mode 360.04; state; measure "360 Hz, sans PSR"
  mode 60.04;  state; measure "60 Hz, sans PSR"

  echo; echo "##### PSR1 forcé"
  since=$(date '+%Y-%m-%d %H:%M:%S')
  echo 0x04 >/sys/module/drm/parameters/debug
  echo 0x3 >"$PSRDBG"
  mode 360.04; state
  mode 60.04;  state
  echo "$dbg_old" >/sys/module/drm/parameters/debug
  echo "--- décisions PSR du pilote :"
  journalctl -k --no-pager -S "$since" | grep -iE 'psr' | grep -viE 'crtc_state_dump.*selective' \
    | sed 's/^.*\]\] //' | sort | uniq -c | sort -rn | head -20
  measure "60 Hz, PSR1 forcé"
  mode 360.04; state
  measure "360 Hz, PSR1 forcé"
} 2>&1 | tee "$OUT"

restore; trap - EXIT
echo "PSR remis par défaut, écran à 360 Hz : $(hypr monitors | grep -oE '[0-9]+x[0-9]+@[0-9.]+' | head -1)" | tee -a "$OUT"
chown "$utilisateur:" "$OUT"
