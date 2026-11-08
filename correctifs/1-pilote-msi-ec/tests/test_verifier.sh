#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests de verifier.sh : sans privilèges, sur un faux sysfs.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/devices/platform/msi-ec/cpu" "$RACINE/sys/class/power_supply/BAT0"
    echo Battery >"$RACINE/sys/class/power_supply/BAT0/type"
    echo 80 >"$RACINE/sys/class/power_supply/BAT0/charge_control_end_threshold"
    : >"$RACINE/sys/devices/platform/msi-ec/cpu/fan_curve"
    : >"$RACINE/sys/devices/platform/msi-ec/fan_mode"
    faux_cmd id 'echo 1000'
    faux_cmd stat 'echo "${GROUPE_FAUX:-msi-ec}"'
}
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

preparer
verifier; code=$?
verifie "sain : code 0" test "$code" -eq 0
verifie "sain : sortie OK" grep -q '^OK ' "$RACINE/sortie"

preparer
rm -rf "$RACINE/sys/devices/platform/msi-ec"
verifier; code=$?
verifie "msi-ec absent : code 1" test "$code" -eq 1
verifie "msi-ec absent : sortie ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

preparer
rm "$RACINE/sys/devices/platform/msi-ec/cpu/fan_curve"
verifier; code=$?
verifie "pilote d'origine : code 2" test "$code" -eq 2
verifie "pilote d'origine : détail" grep -q "^DÉFAUT .*pilote d'origine" "$RACINE/sortie"

preparer
GROUPE_FAUX=root verifier; code=$?
verifie "mauvais groupe : code 2" test "$code" -eq 2
verifie "mauvais groupe : détail" grep -q '^DÉFAUT .*groupe' "$RACINE/sortie"

preparer
echo 100 >"$RACINE/sys/class/power_supply/BAT0/charge_control_end_threshold"
verifier; code=$?
verifie "mauvais seuil : code 2" test "$code" -eq 2
verifie "mauvais seuil : détail" grep -q '^DÉFAUT .*seuil' "$RACINE/sortie"
fin
