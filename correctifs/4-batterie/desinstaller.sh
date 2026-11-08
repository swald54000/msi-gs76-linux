#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire le cache batterie et le rafraîchissement en tâche de fond.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
FICHIERS=(/usr/local/bin/battery-refresh /etc/systemd/system/battery-refresh.service
    /etc/systemd/system/battery-refresh.timer /etc/tmpfiles.d/battery-cache.conf
    /etc/msi-gs76-linux/batterie.conf)
PARAM=/sys/module/battery/parameters/cache_time
ORIGINE="$RACINE/var/lib/msi-gs76-linux/batterie-cache_time.origine"

exiger_root

systemctl disable --now battery-refresh.timer || avertir "minuteur déjà désactivé."
for f in "${FICHIERS[@]}"; do
    if a_une_sauvegarde "$f"; then
        restaurer "$f"
    else
        rm -f "${RACINE:?}$f"
    fi
done
rmdir --ignore-fail-on-non-empty "$RACINE/etc/msi-gs76-linux" 2>/dev/null || true

if [ -r "$ORIGINE" ] && [ -w "$RACINE$PARAM" ]; then
    cat "$ORIGINE" >"$RACINE$PARAM"
fi
rm -f "$ORIGINE"
systemctl daemon-reload

ok "cache batterie et rafraîchissement retirés."
