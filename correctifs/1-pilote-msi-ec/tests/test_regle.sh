#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests de regle-udev.sh et de la validation de SEUIL_CHARGE par installer.sh.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"
. "$corr/regle-udev.sh"

regle="$(regle_udev msi-ec 80 BAT0)"
verifie "règle : chgrp msi-ec" grep -q 'chgrp msi-ec' <<<"$regle"
verifie "règle : chemin de la batterie" grep -q 'BAT0/charge_control_end_threshold' <<<"$regle"
verifie "règle : echo 80" grep -q 'echo 80 ' <<<"$regle"
verifie "règle : pas de gamemode" bash -c '! grep -q game""mode <<<"$1"' _ "$regle"
verifie "règle : pas de BAT1" bash -c '! grep -q BAT""1 <<<"$1"' _ "$regle"
verifie "règle : une seule ligne" test "$(wc -l <<<"$regle")" -eq 1
verifie "règle : chemins /sys réels" grep -q '/sys/devices/platform/msi-ec' <<<"$regle"

# Seuil invalide : installer.sh s'arrête avant tout appel à dkms.
for seuil in 49 101 abc ""; do
    faux_systeme
    faux_cmd id 'echo 0'
    faux_cmd dkms 'echo "$@" >>"$RACINE/journal-dkms"'
    faux_cmd git 'echo "$@" >>"$RACINE/journal-git"'
    SUDO_USER=alice SEUIL_CHARGE="$seuil" bash "$corr/installer.sh" >"$RACINE/sortie" 2>&1
    code=$?
    verifie "SEUIL_CHARGE='$seuil' refusé (code $code)" test "$code" -ne 0
    verifie "SEUIL_CHARGE='$seuil' : dkms jamais appelé" test ! -e "$RACINE/journal-dkms"
    verifie "SEUIL_CHARGE='$seuil' : git jamais appelé" test ! -e "$RACINE/journal-git"
done
fin
