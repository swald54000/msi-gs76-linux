#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire le complément qui fait attendre RAPL à thermald.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
CONF=/etc/systemd/system/thermald.service.d/wait-rapl.conf

exiger_root

if a_une_sauvegarde "$CONF"; then
    restaurer "$CONF"
else
    rm -f "${RACINE:?}$CONF"
fi
rmdir --ignore-fail-on-non-empty "$RACINE$(dirname "$CONF")" 2>/dev/null || true
systemctl daemon-reload

ok "complément thermald retiré."
