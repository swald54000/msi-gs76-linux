#!/usr/bin/env bash
# shellcheck disable=SC1091
# Fait attendre RAPL (jusqu'à 5 s) à thermald avant son démarrage. Utile avec le correctif 2.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
CONF=/etc/systemd/system/thermald.service.d/wait-rapl.conf

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done

exiger_root
verifier_materiel "${forcer[@]}" || exit 1

sauvegarder "$CONF"
mkdir -p "$RACINE$(dirname "$CONF")"
install -m644 "$ici/wait-rapl.conf" "$RACINE$CONF"
systemctl daemon-reload

ok "complément thermald installé : il s'applique au prochain démarrage de thermald."
info "vérification (à titre indicatif, sans effet sur le résultat de l'installation) :"
bash "$ici/verifier.sh" || true
