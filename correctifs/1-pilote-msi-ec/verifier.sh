#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie le pilote msi-ec corrigé. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
seuil_attendu="${SEUIL_CHARGE-80}"
pilote="$RACINE/sys/devices/platform/msi-ec"

if [ ! -d "$pilote" ]; then
    echo "ABSENT pilote msi-ec non chargé"
    exit 1
fi
if [ ! -e "$pilote/cpu/fan_curve" ]; then
    echo "DÉFAUT pilote d'origine chargé (cpu/fan_curve absent) : installer le correctif 1"
    exit 2
fi
groupe="$(stat -c %G "$pilote/fan_mode" 2>/dev/null || true)"
if [ "$groupe" != "msi-ec" ]; then
    echo "DÉFAUT groupe de fan_mode : « ${groupe:-inconnu} » au lieu de msi-ec (règle udev non appliquée)"
    exit 2
fi
chemin_bat="$(batterie)" || { echo "DÉFAUT aucune batterie détectée"; exit 2; }
seuil="$(cat "$chemin_bat/charge_control_end_threshold" 2>/dev/null || true)"
if [ "$seuil" != "$seuil_attendu" ]; then
    echo "DÉFAUT seuil de charge : ${seuil:-illisible} au lieu de $seuil_attendu"
    exit 2
fi
echo "OK msi-ec du fork actif, groupe msi-ec, seuil de charge $seuil %"
exit 0
