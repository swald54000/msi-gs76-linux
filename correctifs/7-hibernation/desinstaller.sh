#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire l'unité qui relance thermald au retour d'hibernation.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
NOM=thermald-apres-hibernation.service
UNITE=/etc/systemd/system/$NOM

exiger_root

systemctl disable "$NOM" 2>/dev/null || true
if a_une_sauvegarde "$UNITE"; then
    restaurer "$UNITE"
else
    rm -f "$RACINE$UNITE"
fi
systemctl daemon-reload

ok "unité retirée : thermald n'est plus relancé au retour d'hibernation."
