#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire la SSDT du GS76 : retour aux seules tables du BIOS.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
DOSSIER=/etc/initcpio/acpi_override
AML=$DOSSIER/ssdt-gs76.aml
CONF=/etc/mkinitcpio.conf.d/zz-acpi-override.conf

exiger_root

# Table : on remet l'éventuelle version d'origine, sinon on la supprime.
if a_une_sauvegarde "$AML"; then
    restaurer "$AML"
else
    rm -f "$RACINE$AML"
fi

# Conf : retirée seulement s'il ne reste aucune autre table .aml.
reste=0
for f in "$RACINE$DOSSIER"/*.aml; do
    [ -e "$f" ] && reste=1
done
if [ "$reste" -eq 0 ]; then
    if a_une_sauvegarde "$CONF"; then
        restaurer "$CONF"
    else
        rm -f "$RACINE$CONF"
    fi
    rmdir --ignore-fail-on-non-empty "$RACINE$DOSSIER" 2>/dev/null || true
else
    info "d'autres tables .aml subsistent dans $DOSSIER : $CONF conservé."
fi

info "reconstruction des initramfs"
reconstruire_initramfs

ok "SSDT retirée au prochain démarrage."
