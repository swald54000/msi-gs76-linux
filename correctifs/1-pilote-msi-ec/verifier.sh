#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie le pilote msi-ec et ses réglages. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
# Seuil attendu : SEUIL_CHARGE s'il est défini, sinon celui de la règle installée, sinon 80.
if [ -n "${SEUIL_CHARGE+x}" ]; then
    seuil_attendu="$SEUIL_CHARGE"
else
    seuil_attendu="$(sed -n 's/.*echo \([0-9][0-9]*\) >.*/\1/p' "$RACINE/etc/udev/rules.d/99-msi-ec.rules" 2>/dev/null | head -n 1)"
    seuil_attendu="${seuil_attendu:-80}"
fi
pilote="$RACINE/sys/devices/platform/msi-ec"

if [ ! -d "$pilote" ]; then
    echo "ABSENT pilote msi-ec non chargé"
    exit 1
fi
if [ ! -e "$pilote/fan_mode" ]; then
    echo "DÉFAUT pilote msi-ec chargé sans fan_mode : ce firmware n'est pas reconnu par le pilote"
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
version_module="$(cat "$RACINE/sys/module/msi_ec/version" 2>/dev/null || true)"
[ -n "$version_module" ] || version_module="$(modinfo -F version msi_ec 2>/dev/null || true)"
echo "OK msi-ec actif (module version ${version_module:-inconnue}), groupe msi-ec, seuil de charge $seuil %"
exit 0
