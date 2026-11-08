#!/usr/bin/env bash
# shellcheck disable=SC1091
# Installe le cache batterie de 5 min et le rafraîchissement en tâche de fond.
# Variables : CACHE_BATTERIE_MS (défaut 300000), RAFRAICHISSEMENT (secondes, défaut 30).
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
CACHE_BATTERIE_MS="${CACHE_BATTERIE_MS:-300000}"
RAFRAICHISSEMENT="${RAFRAICHISSEMENT:-30}"
SCRIPT=/usr/local/bin/battery-refresh
SERVICE=/etc/systemd/system/battery-refresh.service
TIMER=/etc/systemd/system/battery-refresh.timer
TMPF=/etc/tmpfiles.d/battery-cache.conf
CONF=/etc/msi-gs76-linux/batterie.conf
PARAM=/sys/module/battery/parameters/cache_time
ORIGINE="$RACINE/var/lib/msi-gs76-linux/batterie-cache_time.origine"

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done

exiger_root
verifier_materiel "${forcer[@]}" || exit 1

# Validation avant tout changement.
case "$CACHE_BATTERIE_MS" in
    '' | *[!0-9]* | 0*) echec "CACHE_BATTERIE_MS doit être un entier strictement positif (reçu « $CACHE_BATTERIE_MS »)."; exit 1 ;;
esac
if [ "${#CACHE_BATTERIE_MS}" -gt 7 ] || [ "$CACHE_BATTERIE_MS" -gt 3600000 ]; then
    echec "CACHE_BATTERIE_MS ne doit pas dépasser 3600000 (une heure) ; reçu « $CACHE_BATTERIE_MS »."
    exit 1
fi
case "$RAFRAICHISSEMENT" in
    '' | *[!0-9]* | 0*) echec "RAFRAICHISSEMENT doit être un entier strictement positif, en secondes (reçu « $RAFRAICHISSEMENT »)."; exit 1 ;;
esac
bat="$(batterie)" || { echec "aucune batterie détectée dans /sys/class/power_supply."; exit 1; }
bat="${bat#"$RACINE"}"

# Valeur d'origine du cache, mémorisée une seule fois.
if [ ! -e "$ORIGINE" ] && [ -r "$RACINE$PARAM" ]; then
    mkdir -p "$(dirname "$ORIGINE")"
    cat "$RACINE$PARAM" >"$ORIGINE"
fi

for f in "$SCRIPT" "$SERVICE" "$TIMER" "$TMPF" "$CONF"; do
    sauvegarder "$f"
done

mkdir -p "$RACINE$(dirname "$SCRIPT")" "$RACINE$(dirname "$SERVICE")" \
    "$RACINE$(dirname "$TMPF")" "$RACINE$(dirname "$CONF")"
install -m755 "$ici/battery-refresh" "$RACINE$SCRIPT"
install -m644 "$ici/battery-refresh.service" "$RACINE$SERVICE"
sed "s/^OnUnitActiveSec=.*/OnUnitActiveSec=${RAFRAICHISSEMENT}s/" "$ici/battery-refresh.timer" >"$RACINE$TIMER"
chmod 644 "$RACINE$TIMER"
printf 'w /sys/module/battery/parameters/cache_time - - - - %s\n' "$CACHE_BATTERIE_MS" >"$RACINE$TMPF"
printf 'BATTERIE=%s\nCACHE_BATTERIE_MS=%s\n' "$bat" "$CACHE_BATTERIE_MS" >"$RACINE$CONF"

if [ -w "$RACINE$PARAM" ]; then
    echo "$CACHE_BATTERIE_MS" >"$RACINE$PARAM"
else
    avertir "paramètre $PARAM non modifiable : le cache s'appliquera au prochain démarrage."
fi
systemctl daemon-reload
systemctl enable --now battery-refresh.timer

ok "cache batterie de ${CACHE_BATTERIE_MS} ms, rafraîchissement toutes les ${RAFRAICHISSEMENT} s (batterie : $bat)."
info "vérification (à titre indicatif, sans effet sur le résultat de l'installation) :"
bash "$ici/verifier.sh" || true
