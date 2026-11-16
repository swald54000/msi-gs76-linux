#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie le correctif d'hibernation. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
NOM=thermald-apres-hibernation.service
unite="$RACINE/etc/systemd/system/$NOM"

if [ ! -f "$unite" ]; then
    echo "ABSENT relance de thermald après hibernation non installée"
    exit 1
fi
if ! cmp -s "$ici/$NOM" "$unite"; then
    echo "DÉFAUT unité différente de la version du dépôt : relancer l'installateur"
    exit 2
fi
if ! systemctl is-enabled "$NOM" >/dev/null 2>&1; then
    echo "DÉFAUT unité présente mais non activée : relancer l'installateur"
    exit 2
fi
echo "OK thermald est relancé au retour d'hibernation (limites de puissance réappliquées)"
exit 0
