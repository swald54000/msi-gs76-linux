#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Qu'est-ce qui maintient le package CPU en PC2 au repos ?
# Étapes cumulatives de 15 s : 0 référence, 1 PSR forcé, 2 périphériques USB externes
# coupés, 3 Ethernet et lecteur de cartes coupés.
# Tout est restauré à la fin (y compris sur Ctrl-C). Les souris et claviers USB externes
# cessent de répondre ~40 s ; le clavier et le pavé tactile du portable restent actifs.
# Adresses PCI de l'Ethernet et du lecteur de cartes : celles du GS76 (ETH, CARD).
# Écrit ./diag-idle2.txt (dossier courant). Ne pas toucher au portable (~2 min).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root

OUT="$PWD/diag-idle2.txt"
proprio="$(utilisateur_cible 2>/dev/null || true)"
DBG=/sys/kernel/debug
RAPL=/sys/class/powercap/intel-rapl:0/energy_uj
exec > >(tee "$OUT") 2>&1
mountpoint -q $DBG || mount -t debugfs none $DBG
modprobe intel_pmc_core 2>/dev/null

I915=""
for d in "$DBG"/dri/*; do [[ -r $d/name ]] && grep -q i915 "$d"/name && I915=$d && break; done
PSRDBG="$I915"/i915_edp_psr_debug

# Périphériques USB externes (tout ce qui est sur le xHCI sauf le Bluetooth intégré)
USBDEVS=()
for u in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
  [[ -f $u/idVendor && ! $u == *:* ]] || continue
  [[ $(<"$u"/idVendor):$(<"$u"/idProduct) == 8087:0032 ]] && continue
  USBDEVS+=("$u")
done

ETH=0000:59:00.0
CARD=0000:5a:00.0
ethdrv=$(basename "$(readlink /sys/bus/pci/devices/$ETH/driver)" 2>/dev/null)
carddrv=$(basename "$(readlink /sys/bus/pci/devices/$CARD/driver)" 2>/dev/null)
psr_old=$(cat "$PSRDBG" 2>/dev/null)

restore() {
  [[ -n $psr_old && -w $PSRDBG ]] && echo "$psr_old" >"$PSRDBG" 2>/dev/null
  for u in "${USBDEVS[@]}"; do echo 1 >"$u/authorized" 2>/dev/null; done
  [[ -n $ethdrv && ! -e /sys/bus/pci/devices/$ETH/driver ]] && echo $ETH >/sys/bus/pci/drivers/"$ethdrv"/bind 2>/dev/null
  [[ -n $carddrv && ! -e /sys/bus/pci/devices/$CARD/driver ]] && echo $CARD >/sys/bus/pci/drivers/"$carddrv"/bind 2>/dev/null
}
trap restore EXIT

measure() {
  local label=$1 a b e0 e1
  sleep 5
  a=$(cat $DBG/pmc_core/package_cstate_show); e0=$(<$RAPL)
  sleep 15
  b=$(cat $DBG/pmc_core/package_cstate_show); e1=$(<$RAPL)
  printf '===== %-40s ' "$label"
  awk -v e0="$e0" -v e1="$e1" 'BEGIN{printf "%.2f W  ", (e1-e0)/15e6}'
  paste <(echo "$a") <(echo "$b") | awk -F'\t' '{split($1,x,":"); split($2,y,":"); v=(y[2]-x[2])/150000; if (v>=0.1) printf "%s %.1f%%  ", x[1], v}'
  echo
}

echo "Paramètre i915 enable_psr = $(cat /sys/module/i915/parameters/enable_psr 2>/dev/null)  psr_debug = $psr_old"
echo "Périphériques USB coupés à l'étape 2 :"
for u in "${USBDEVS[@]}"; do echo "  $(basename "$u") $(cat "$u"/product 2>/dev/null)"; done
echo

measure "0. Référence"

if [[ -w $PSRDBG ]]; then
  echo 0x3 >"$PSRDBG" 2>/dev/null || echo 0x2 >"$PSRDBG" 2>/dev/null
  sleep 2
  echo "--- PSR après forçage :"; grep -E 'PSR mode|Source PSR status|Busy|PSR1|reason' "$I915"/i915_edp_psr_status | head -6
fi
measure "1. + PSR forcé"
echo "--- DMC (états DC de l'affichage) :"; grep -E 'DC3 -> DC5|DC5 -> DC6' "$I915"/i915_dmc_info

for u in "${USBDEVS[@]}"; do echo 0 >"$u/authorized"; done
measure "2. + USB externes coupés"

[[ -n $ethdrv ]] && echo $ETH >/sys/bus/pci/drivers/"$ethdrv"/unbind
[[ -n $carddrv ]] && echo $CARD >/sys/bus/pci/drivers/"$carddrv"/unbind
measure "3. + Ethernet et lecteur de cartes coupés"

echo; echo "--- ltr_show (étape 3)"; grep -vE 'RAW: 0x0 ' $DBG/pmc_core/ltr_show

restore; trap - EXIT
echo; echo "Tout est restauré."
[ -n "$proprio" ] && chown "$proprio:" "$OUT"
echo "Terminé : $OUT"
