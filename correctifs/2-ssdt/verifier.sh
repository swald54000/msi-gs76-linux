#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie la SSDT du GS76. Sans privilèges : les tables ACPI (/sys/firmware/acpi/tables)
# et parfois le journal du noyau sont réservés à root, ces preuves sont donc facultatives.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
aml="$RACINE/etc/initcpio/acpi_override/ssdt-gs76.aml"
conf="$RACINE/etc/mkinitcpio.conf.d/zz-acpi-override.conf"

if [ ! -f "$aml" ] || ! grep -qs '^HOOKS+=(acpi_override)$' "$conf"; then
    echo "ABSENT SSDT non installée (table ou $(basename "$conf") manquant)"
    exit 1
fi

# Précise si l'installation est postérieure au dernier démarrage (redémarrage nécessaire).
btime="$(sed -n 's/^btime \([0-9][0-9]*\)$/\1/p' "$RACINE/proc/stat" 2>/dev/null | head -n 1)"
mtime="$(stat -c %Y "$aml" 2>/dev/null || true)"
if [ -n "$btime" ] && [ -n "$mtime" ] && [ "$mtime" -gt "$btime" ]; then
    cause="installé après le dernier démarrage : redémarrer"
else
    cause="chargement absent malgré un démarrage postérieur à l'installation"
fi

preuves=""

# Journal du noyau du démarrage en cours.
if journal="$(journalctl -k -b 2>/dev/null)" && [ -n "$journal" ]; then
    if grep -q GS76FIX <<<"$journal"; then
        preuves="${preuves} journal"
    else
        echo "DÉFAUT SSDT installée mais absente du journal du noyau (GS76FIX introuvable) : $cause"
        exit 2
    fi
else
    info "journal du noyau illisible sans privilèges : preuve de chargement non vérifiée par le journal"
fi

# Alias PS/2 du pavé tactile : doit avoir disparu.
if grep -qs 'SynPS/2' "$RACINE/proc/bus/input/devices"; then
    echo "DÉFAUT périphérique SynPS/2 présent : l'alias PS/2 du pavé tactile n'est pas masqué (SSDT non chargée) : $cause"
    exit 2
fi

# Tables ACPI : lisibles seulement pour root.
lisibles=0
trouvee=0
for t in "$RACINE"/sys/firmware/acpi/tables/SSDT*; do
    [ -f "$t" ] && [ -r "$t" ] || continue
    lisibles=$((lisibles + 1))
    if grep -aq GS76FIX "$t"; then trouvee=1; fi
done
if [ "$lisibles" -gt 0 ]; then
    if [ "$trouvee" -eq 1 ]; then
        preuves="${preuves} tables-acpi"
    else
        echo "DÉFAUT SSDT installée mais GS76FIX absent des tables ACPI chargées : $cause"
        exit 2
    fi
else
    info "tables ACPI illisibles sans privilèges : non vérifiées"
fi

if [ -n "$preuves" ]; then
    echo "OK SSDT installée et chargée (preuves :${preuves}), pas d'alias SynPS/2"
else
    echo "OK SSDT installée, aucun signe de non-chargement (pas d'alias SynPS/2) ; chargement non prouvé sans privilèges"
fi
exit 0
