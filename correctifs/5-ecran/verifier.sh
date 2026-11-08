#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie le PSR forcé et la fréquence selon l'alimentation. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> pour chaque partie ; code 0 sain, 1 rien
# d'installé, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
psr="$RACINE/etc/systemd/system/i915-psr-force.service"
script="$RACINE/usr/local/bin/edp-refresh-auto"
unite="$RACINE/etc/systemd/user/edp-refresh-auto.service"
lien="$RACINE/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service"

code=0
installes=0

# PSR forcé
if [ ! -f "$psr" ]; then
    echo "ABSENT PSR forcé non installé"
else
    installes=$((installes + 1))
    if systemctl is-active i915-psr-force >/dev/null 2>&1; then
        echo "OK PSR forcé : service i915-psr-force actif"
    else
        echo "DÉFAUT PSR forcé : service i915-psr-force inactif (voir systemctl status i915-psr-force)"
        code=2
    fi
fi

# Fréquence selon l'alimentation
if [ ! -f "$script" ] && [ ! -f "$unite" ]; then
    echo "ABSENT fréquence selon l'alimentation non installée"
else
    installes=$((installes + 1))
    if [ ! -x "$script" ] || [ ! -f "$unite" ]; then
        echo "DÉFAUT fréquence : script ou unité manquant (relancer l'installateur)"
        code=2
    elif [ ! -L "$lien" ] && ! systemctl --global is-enabled edp-refresh-auto.service >/dev/null 2>&1; then
        echo "DÉFAUT fréquence : unité utilisateur non activée"
        code=2
    else
        echo "OK fréquence : unité utilisateur activée"
    fi
fi

[ "$installes" -eq 0 ] && exit 1
exit "$code"
