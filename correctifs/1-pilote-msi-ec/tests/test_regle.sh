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
verifie "règle : pas de l'ancien groupe d'accès" bash -c '! grep -q game""mode <<<"$1"' _ "$regle"
verifie "règle : pas d'autre batterie codée en dur" bash -c '! grep -q BAT""1 <<<"$1"' _ "$regle"
verifie "règle : une seule ligne" test "$(wc -l <<<"$regle")" -eq 1
verifie "règle : chemins /sys réels" grep -q '/sys/devices/platform/msi-ec' <<<"$regle"

# Faux GS76 complet (DMI, firmware, batterie) : le matériel est reconnu, seul le seuil est en cause.
gs76() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id" "$RACINE/sys/class/power_supply/BAT0" "$RACINE/faux-src"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    echo Battery >"$RACINE/sys/class/power_supply/BAT0/type"
    echo '@VERSION@' >"$RACINE/faux-src/dkms.conf"
    faux_cmd id 'echo 0'
    faux_cmd git 'echo "git $*" >>"$RACINE/journal-git"
case "$*" in *archive*) tar -C "$RACINE/faux-src" -cf - . ;; esac'
    for c in dkms getent groupadd usermod gpasswd groupdel modprobe udevadm systemctl snapper mkinitcpio limine-mkinitcpio; do
        faux_cmd "$c" "echo \"$c \$*\" >>\"\$RACINE/journal-dkms\"; exit 0"
    done
    export SUDO_USER=alice MSI_EC_NOYAUX=""
}

# Seuil invalide : message de validation, et ni git ni dkms ne sont appelés.
for seuil in 49 101 abc ""; do
    gs76
    SEUIL_CHARGE="$seuil" bash "$corr/installer.sh" >"$RACINE/sortie" 2>&1
    code=$?
    verifie "SEUIL_CHARGE='$seuil' refusé (code $code)" test "$code" -ne 0
    verifie "SEUIL_CHARGE='$seuil' : message de validation" grep -q 'SEUIL_CHARGE invalide' "$RACINE/sortie"
    verifie "SEUIL_CHARGE='$seuil' : dkms jamais appelé" test ! -e "$RACINE/journal-dkms"
    verifie "SEUIL_CHARGE='$seuil' : git jamais appelé" test ! -e "$RACINE/journal-git"
done

# Bornes acceptées : la validation passe et l'installation atteint l'étape git.
for seuil in 50 100; do
    gs76
    SEUIL_CHARGE="$seuil" bash "$corr/installer.sh" >"$RACINE/sortie" 2>&1
    verifie "SEUIL_CHARGE=$seuil : pas de message de validation" bash -c '! grep -q "SEUIL_CHARGE invalide" "$1"' _ "$RACINE/sortie"
    verifie "SEUIL_CHARGE=$seuil : l'étape git est atteinte" test -e "$RACINE/journal-git"
done
fin
