#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie la fréquence selon l'alimentation. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 rien d'installé, 2 défaut.
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

# Ancien PSR forcé : remplacé par la VBT corrigée ; sa présence est un reste à retirer.
if [ -f "$psr" ]; then
    installes=$((installes + 1))
    echo "DÉFAUT ancien service i915-psr-force encore installé : relancer l'installateur (le PSR est assuré par le correctif 8)"
    code=2
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
