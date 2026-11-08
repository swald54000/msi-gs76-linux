#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Pourquoi le PSR reste-t-il coupé à 60 Hz avec
# i915.enable_psr=1 ? À lancer sur batterie (écran à 60 Hz).
# Journalise les décisions PSR d'i915 pendant un aller-retour 360 -> 60 Hz.
# L'écran clignote deux fois. Écrit ./diag-psr2.txt (dossier courant).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
utilisateur="$(utilisateur_cible)" || exit 1
uid_utilisateur="$(id -u "$utilisateur")"

OUT="$PWD/diag-psr2.txt"
DBG=/sys/kernel/debug
I915=""
for d in "$DBG"/dri/*; do [[ -r $d/name ]] && grep -q i915 "$d"/name && I915=$d && break; done

# hyprctl dans la session Hyprland de l'utilisateur qui a lancé sudo.
hypr() {
  local sig
  sig=$(find "/run/user/$uid_utilisateur/hypr" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | head -1)
  runuser -u "$utilisateur" -- env XDG_RUNTIME_DIR="/run/user/$uid_utilisateur" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@"
}
mode() { hypr eval "hl.monitor({ output = \"eDP-2\", mode = \"1920x1080@$1\", position = \"0x0\", scale = 1 })" >/dev/null; sleep 3; }

dbg_old=$(cat /sys/module/drm/parameters/debug)
trap 'echo "$dbg_old" >/sys/module/drm/parameters/debug' EXIT
{
  echo "enable_psr=$(cat /sys/module/i915/parameters/enable_psr)  psr_debug=$(cat "$I915"/i915_edp_psr_debug)"
  echo "cmdline: $(tr ' ' '\n' </proc/cmdline | grep i915)"
  since=$(date '+%Y-%m-%d %H:%M:%S')
  echo 0x04 >/sys/module/drm/parameters/debug
  mode 360.04
  mode 60.04
  echo "$dbg_old" >/sys/module/drm/parameters/debug
  echo "--- décisions PSR :"
  journalctl -k --no-pager -S "$since" | grep -iE 'psr|vbt' | sed 's/^.*\]\] //' | sort | uniq -c | sort -rn | head -20
  echo "--- état :"; head -4 "$I915"/i915_edp_psr_status
} 2>&1 | tee "$OUT"
chown "$utilisateur:" "$OUT"
