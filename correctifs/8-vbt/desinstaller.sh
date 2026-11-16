#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire la VBT corrigée : i915 reprend la VBT du BIOS au prochain démarrage.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
FW=/usr/lib/firmware/updates/gs76/vbt-auo-e295.bin
MODPROBE=/etc/modprobe.d/gs76-vbt.conf
INITCPIO=/etc/mkinitcpio.conf.d/zz-gs76-vbt.conf

exiger_root

for f in "$FW" "$MODPROBE" "$INITCPIO"; do
    if a_une_sauvegarde "$f"; then
        restaurer "$f"
    else
        rm -f "$RACINE$f"
    fi
done
rmdir --ignore-fail-on-non-empty "$RACINE$(dirname "$FW")" 2>/dev/null || true

info "reconstruction des initramfs"
if ! reconstruire_initramfs; then
    echec "la reconstruction de l'initramfs a échoué : l'ancien initramfs référence encore la VBT corrigée. Relancer limine-mkinitcpio (ou mkinitcpio -P)."
    exit 1
fi

ok "VBT corrigée retirée : redémarrer pour revenir à la VBT du BIOS."
