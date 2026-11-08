#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie le cache batterie et le minuteur de rafraîchissement. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
script="$RACINE/usr/local/bin/battery-refresh"
tmpf="$RACINE/etc/tmpfiles.d/battery-cache.conf"
conf="$RACINE/etc/msi-gs76-linux/batterie.conf"
param="$RACINE/sys/module/battery/parameters/cache_time"

if [ ! -f "$script" ] && [ ! -f "$tmpf" ] && [ ! -f "$conf" ]; then
    echo "ABSENT correctif batterie non installé"
    exit 1
fi
for f in "$script" "$tmpf" "$conf"; do
    if [ ! -f "$f" ]; then
        echo "DÉFAUT fichier manquant : ${f#"$RACINE"} (relancer l'installateur)"
        exit 2
    fi
done

attendu="$(awk '{print $NF}' "$tmpf")"
actuel="$(cat "$param" 2>/dev/null || true)"
if [ "$actuel" != "$attendu" ]; then
    echo "DÉFAUT cache_time vaut « ${actuel:-illisible} » au lieu de $attendu ms"
    exit 2
fi
if ! systemctl is-enabled battery-refresh.timer >/dev/null 2>&1; then
    echo "DÉFAUT minuteur battery-refresh.timer non activé"
    exit 2
fi
echo "OK cache_time à $attendu ms, minuteur de rafraîchissement activé"
exit 0
