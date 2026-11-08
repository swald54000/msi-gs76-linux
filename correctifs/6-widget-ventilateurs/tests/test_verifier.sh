#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Tests de verifier.sh du correctif 6 : sans privilèges, faux sysfs et faux id/stat.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

preparer() {
    faux_systeme
    HOME="$RACINE/home"
    export HOME
    mkdir -p "$HOME/.config/omarchy/plugins/swald.fans" "$RACINE/sys/devices/platform/msi-ec"
    echo '{}' >"$HOME/.config/omarchy/plugins/swald.fans/manifest.json"
    : >"$RACINE/sys/devices/platform/msi-ec/fan_mode"
    faux_cmd id 'echo "${GROUPES_FAUX:-user wheel msi-ec}"'
    faux_cmd stat 'echo "${STAT_FAUX:-msi-ec -rw-rw----}"'
}
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

preparer
verifier; code=$?
verifie "sain : code 0" test "$code" -eq 0
verifie "sain : sortie OK" grep -q '^OK ' "$RACINE/sortie"

preparer
rm "$HOME/.config/omarchy/plugins/swald.fans/manifest.json"
verifier; code=$?
verifie "plugin absent : code 1" test "$code" -eq 1
verifie "plugin absent : sortie ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

preparer
GROUPES_FAUX="user wheel" verifier; code=$?
verifie "hors groupe : code 2" test "$code" -eq 2
verifie "hors groupe : détail" grep -q '^DÉFAUT .*msi-ec.*reconnect' "$RACINE/sortie"

preparer
STAT_FAUX="root -rw-r--r--" verifier; code=$?
verifie "mauvais groupe de fan_mode : code 2" test "$code" -eq 2
verifie "mauvais groupe de fan_mode : détail" grep -q '^DÉFAUT .*fan_mode.*msi-ec' "$RACINE/sortie"

preparer
STAT_FAUX="msi-ec -rw-r--r--" verifier; code=$?
verifie "fan_mode non inscriptible par le groupe : code 2" test "$code" -eq 2
verifie "fan_mode non inscriptible : détail" grep -q '^DÉFAUT .*fan_mode.*inscriptible' "$RACINE/sortie"

preparer
rm -rf "$RACINE/sys/devices/platform/msi-ec"
verifier; code=$?
verifie "msi-ec absent : code 2" test "$code" -eq 2
verifie "msi-ec absent : détail" grep -q '^DÉFAUT .*msi-ec' "$RACINE/sortie"
fin
