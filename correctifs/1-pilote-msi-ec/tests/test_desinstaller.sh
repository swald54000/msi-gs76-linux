#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests de desinstaller.sh : règle restaurée, groupe supprimé seulement s'il est vide.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

preparer() { # $1 = membres du groupe
    faux_systeme
    mkdir -p "$RACINE/etc/udev/rules.d" "$RACINE/usr/src/msi-ec-r734.d7fbbd8" \
        "$RACINE/usr/src/msi-ec-gs76.4b72e41" "$RACINE/usr/lib/modules/7.2.14-1-omarchy/build" \
        "$RACINE/var/lib/msi-gs76-linux"
    echo "regle d'origine" >"$RACINE/etc/udev/rules.d/99-msi-ec.rules"
    echo r734.d7fbbd8 >"$RACINE/var/lib/msi-gs76-linux/pilote-precedent"
    faux_cmd id 'echo 0'
    faux_cmd dkms 'echo "dkms $*" >>"$RACINE/journal"
[ "$1" = status ] && echo "msi-ec/gs76.4b72e41, 7.2.14-1-omarchy, x86_64: installed"
exit 0'
    echo "$1" >"$RACINE/membres"
    faux_cmd getent 'echo "msi-ec:x:990:$(cat "$RACINE/membres")"'
    faux_cmd gpasswd 'echo "gpasswd $*" >>"$RACINE/journal"
[ "$1" = -d ] && { sed -i "s/\\b$2\\b//; s/^,//; s/,$//; s/,,/,/" "$RACINE/membres"; }
exit 0'
    export SUDO_USER=alice
    faux_cmd groupdel 'echo "groupdel $*" >>"$RACINE/journal"'
    for c in modprobe udevadm; do faux_cmd "$c" 'exit 0'; done
    # Simule l'installation : sauvegarde de la règle d'origine puis règle du fork.
    # shellcheck source=../../../lib/commun.sh
    . "$ici/../../../lib/commun.sh"
    sauvegarder /etc/udev/rules.d/99-msi-ec.rules
    echo "regle du fork" >"$RACINE/etc/udev/rules.d/99-msi-ec.rules"
    export MSI_EC_NOYAUX="7.2.14-1-omarchy"
}

preparer ""
bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "règle d'origine restaurée" grep -q "regle d'origine" "$RACINE/etc/udev/rules.d/99-msi-ec.rules"
verifie "module du fork retiré" grep -q 'dkms remove msi-ec/gs76.4b72e41 --all' "$RACINE/journal"
verifie "sources du fork supprimées" test ! -d "$RACINE/usr/src/msi-ec-gs76.4b72e41"
verifie "version précédente réinstallée" grep -q 'dkms install msi-ec/r734.d7fbbd8 -k 7.2.14-1-omarchy' "$RACINE/journal"
verifie "groupe vide supprimé" grep -q 'groupdel msi-ec' "$RACINE/journal"

# L'utilisateur est retiré du groupe avant le test « groupe vide ».
preparer "alice"
bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1
verifie "utilisateur retiré du groupe" grep -q '^gpasswd -d alice msi-ec' "$RACINE/journal"
verifie "seul membre retiré : groupe supprimé" grep -q 'groupdel msi-ec' "$RACINE/journal"
verifie "gpasswd avant groupdel" bash -c '[ "$(grep -n "^gpasswd" "$1" | head -1 | cut -d: -f1)" -lt "$(grep -n "^groupdel" "$1" | head -1 | cut -d: -f1)" ]' _ "$RACINE/journal"

preparer "alice,bob"
bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1
verifie "groupe avec un autre membre conservé" bash -c '! grep -q groupdel "$1"' _ "$RACINE/journal"
verifie "autre membre mentionné" grep -q 'membres : bob' "$RACINE/sortie"

# Sans SUDO_USER : avertissement, pas d'arrêt.
preparer ""
unset SUDO_USER
bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; code=$?
verifie "sans SUDO_USER : code 0" test "$code" -eq 0
verifie "sans SUDO_USER : gpasswd non appelé" bash -c '! grep -q "^gpasswd" "$1"' _ "$RACINE/journal"
fin
