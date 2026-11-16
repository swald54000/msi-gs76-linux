#!/usr/bin/env bash
# shellcheck disable=SC1091
# Relance thermald au retour d'hibernation pour qu'il réapplique les limites de puissance.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
NOM=thermald-apres-hibernation.service
UNITE=/etc/systemd/system/$NOM

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done

exiger_root
verifier_materiel "${forcer[@]}" || exit 1

sauvegarder "$UNITE"
mkdir -p "$RACINE$(dirname "$UNITE")"
install -m644 "$ici/$NOM" "$RACINE$UNITE"
systemctl daemon-reload
systemctl enable "$NOM"

ok "unité installée : thermald sera relancé à chaque retour d'hibernation."
info "vérification (à titre indicatif, sans effet sur le résultat de l'installation) :"
bash "$ici/verifier.sh" || true
