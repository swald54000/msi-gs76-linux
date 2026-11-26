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

chargement="/etc/modules-load.d/msi-ec.conf"
# Le pilote d'origine n'a aucun alias matériel : sans une ligne msi_ec dans modules-load.d, rien
# ne le charge au démarrage.
charge_au_demarrage() {
    grep -qsE '^[[:space:]]*msi[-_]ec[[:space:]]*$' "$RACINE"/etc/modules-load.d/*.conf "$RACINE"/usr/lib/modules-load.d/*.conf
}
installe=0
for d in "$RACINE"/usr/src/msi-ec-gs76.*; do [ -d "$d" ] && installe=1; done

if [ ! -d "$pilote" ]; then
    if [ "$installe" = 0 ]; then
        echo "ABSENT pilote msi-ec non chargé"
        exit 1
    fi
    if charge_au_demarrage; then
        echo "DÉFAUT correctif installé mais pilote msi-ec non chargé (essayer : sudo modprobe msi_ec, puis lire le journal du noyau)"
    else
        echo "DÉFAUT correctif installé mais pilote msi-ec non chargé : rien ne le charge au démarrage ($chargement absent), relancer l'installateur"
    fi
    exit 2
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
if ! charge_au_demarrage; then
    echo "DÉFAUT pilote msi-ec chargé, mais rien ne le chargera au prochain démarrage ($chargement absent) : relancer l'installateur"
    exit 2
fi
version_module="$(cat "$RACINE/sys/module/msi_ec/version" 2>/dev/null || true)"
[ -n "$version_module" ] || version_module="$(modinfo -F version msi_ec 2>/dev/null || true)"
echo "OK msi-ec actif (module version ${version_module:-inconnue}), groupe msi-ec, seuil de charge $seuil %"
exit 0
