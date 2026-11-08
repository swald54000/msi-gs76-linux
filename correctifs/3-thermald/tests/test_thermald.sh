#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests du correctif 3 (thermald attend RAPL).
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

CONF=/etc/systemd/system/thermald.service.d/wait-rapl.conf

preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    faux_cmd id 'echo 0'
    faux_cmd systemctl 'echo "systemctl $*" >>"$RACINE/journal"'
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }
desinstaller() { bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; }
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

preparer
verifier; code=$?
verifie "avant installation : code 1" test "$code" -eq 1
verifie "avant installation : ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

installer; code=$?
verifie "installation : code 0" test "$code" -eq 0
verifie "installation : complément présent et identique" cmp -s "$corr/wait-rapl.conf" "$RACINE$CONF"
verifie "installation : daemon-reload appelé" grep -q '^systemctl daemon-reload' "$RACINE/journal"
verifier; code=$?
verifie "après installation : code 0" test "$code" -eq 0
verifie "après installation : OK" grep -q '^OK ' "$RACINE/sortie"

installer; code=$?
verifie "seconde installation : code 0" test "$code" -eq 0
verifie "seconde installation : toujours identique" cmp -s "$corr/wait-rapl.conf" "$RACINE$CONF"

echo "[Service]" >"$RACINE$CONF"
verifier; code=$?
verifie "complément modifié : code 2" test "$code" -eq 2
verifie "complément modifié : DÉFAUT" grep -q '^DÉFAUT ' "$RACINE/sortie"

preparer
installer
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "désinstallation : complément retiré" test ! -e "$RACINE$CONF"
verifie "désinstallation : dossier vide retiré" test ! -d "$RACINE/etc/systemd/system/thermald.service.d"
verifie "désinstallation : daemon-reload appelé" grep -q '^systemctl daemon-reload' "$RACINE/journal"
verifier; code=$?
verifie "après désinstallation : code 1" test "$code" -eq 1

# Complément préexistant différent : restauré.
preparer
mkdir -p "$RACINE/etc/systemd/system/thermald.service.d"
echo "# avant" >"$RACINE$CONF"
installer
desinstaller
verifie "complément préexistant restauré" test "$(cat "$RACINE$CONF")" = "# avant"

# Matériel non reconnu : refus.
preparer
echo Autre >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "matériel inconnu : refus" test "$code" -ne 0
verifie "matériel inconnu : rien installé" test ! -e "$RACINE$CONF"

fin
