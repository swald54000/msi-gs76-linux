#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie le complément thermald. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
conf="$RACINE/etc/systemd/system/thermald.service.d/wait-rapl.conf"

if [ ! -f "$conf" ]; then
    echo "ABSENT complément thermald non installé"
    exit 1
fi
if ! cmp -s "$ici/wait-rapl.conf" "$conf"; then
    echo "DÉFAUT complément thermald différent de la version du dépôt : relancer l'installateur"
    exit 2
fi
echo "OK thermald attend RAPL (jusqu'à 5 s) avant de démarrer"
exit 0
