#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire le PSR forcé et la fréquence de la dalle selon l'alimentation.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
FICHIERS=(/etc/systemd/system/i915-psr-force.service /usr/local/bin/edp-refresh-auto
    /etc/systemd/user/edp-refresh-auto.service)

exiger_root

systemctl disable --now i915-psr-force.service || avertir "service PSR déjà désactivé."
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

ok "PSR forcé et fréquence selon l'alimentation retirés (les sessions ouvertes gardent le script en cours jusqu'à leur fermeture)."
