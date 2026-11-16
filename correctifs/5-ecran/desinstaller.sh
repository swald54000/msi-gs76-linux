#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire la fréquence de la dalle selon l'alimentation (et l'ancien PSR forcé s'il est encore là).
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
FICHIERS=(/etc/systemd/system/i915-psr-force.service /usr/local/bin/edp-refresh-auto
    /etc/systemd/user/edp-refresh-auto.service)

exiger_root

if [ -e "$RACINE/etc/systemd/system/i915-psr-force.service" ]; then
    systemctl disable --now i915-psr-force.service || avertir "ancien service PSR déjà désactivé."
fi
systemctl --global disable edp-refresh-auto.service || avertir "unité utilisateur déjà désactivée."
# Lien d'activation retiré explicitement, même si « disable » a échoué (unité déjà supprimée).
rm -f "$RACINE/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service"
for f in "${FICHIERS[@]}"; do
    if a_une_sauvegarde "$f"; then
        restaurer "$f"
    else
        rm -f "$RACINE$f"
    fi
done
rmdir --ignore-fail-on-non-empty "$RACINE/etc/systemd/user/graphical-session.target.wants" 2>/dev/null || true
systemctl daemon-reload

ok "fréquence selon l'alimentation retirée (les sessions ouvertes gardent le script en cours jusqu'à leur fermeture)."
