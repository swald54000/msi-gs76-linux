#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests de installer.sh : tout se passe sous un RACINE temporaire, avec de faux outils.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

# Prépare un faux système GS76 ; $1 = noyaux (liste séparée par des espaces).
preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id" "$RACINE/sys/class/power_supply/BAT0" \
        "$RACINE/sys/devices/platform/msi-ec/cpu" "$RACINE/faux-src" \
        "$RACINE/usr/src/msi-ec-r734.d7fbbd8"
    echo "Alpha GS76 Stealth" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    echo Battery >"$RACINE/sys/class/power_supply/BAT0/type"
    : >"$RACINE/sys/devices/platform/msi-ec/cpu/fan_curve"
    echo '@VERSION@' >"$RACINE/faux-src/dkms.conf"
    local k
    for k in $1; do mkdir -p "$RACINE/usr/lib/modules/$k/build"; done
    faux_cmd id 'echo 0'
    faux_cmd git 'echo "git $*" >>"$RACINE/journal"
case "$*" in *archive*) tar -C "$RACINE/faux-src" -cf - . ;; esac'
    faux_cmd dkms 'echo "dkms $*" >>"$RACINE/journal"
case "$1" in
  status) echo "msi-ec/r734.d7fbbd8, 7.2.14-1-omarchy, x86_64: installed" ;;
  install) case "$2" in msi-ec/gs76.*) [ "${DKMS_ECHEC:-0}" = 1 ] && exit 1 ;; esac ;;
esac
exit 0'
    faux_cmd getent '[ -e "$RACINE/groupe-existe" ] && { echo "msi-ec:x:990:"; exit 0; }; exit 2'
    faux_cmd groupadd 'echo "groupadd $*" >>"$RACINE/journal"; touch "$RACINE/groupe-existe"'
    faux_cmd usermod 'echo "usermod $*" >>"$RACINE/journal"'
    for c in modprobe udevadm systemctl mkinitcpio limine-mkinitcpio snapper; do
        faux_cmd "$c" "echo \"$c \$*\" >>\"\$RACINE/journal\""
    done
    export SUDO_USER=alice MSI_EC_REF=4b72e41bdeb6d0c9949dd3b16a5dff1a6956ff97
    export MSI_EC_NOYAUX="$1"
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }

# 1. dkms install échoue : retour arrière et version précédente réinstallée.
preparer "7.2.14-1-omarchy"
DKMS_ECHEC=1 installer; code=$?
verifie "échec dkms : code non nul" test "$code" -ne 0
verifie "échec dkms : version précédente réinstallée" grep -q 'dkms install msi-ec/r734.d7fbbd8' "$RACINE/journal"
verifie "échec dkms : pas de sources du fork laissées" bash -c 'ls "$1"/usr/src | grep -vq gs76' _ "$RACINE"
verifie "échec dkms : pas de règle udev" test ! -e "$RACINE/etc/udev/rules.d/99-msi-ec.rules"

# 2. Succès.
preparer "7.2.14-1-omarchy"
installer; code=$?
verifie "succès : code 0" test "$code" -eq 0
verifie "succès : sources dans usr/src" test -f "$RACINE/usr/src/msi-ec-gs76.4b72e41/dkms.conf"
verifie "succès : version substituée" grep -q 'gs76.4b72e41' "$RACINE/usr/src/msi-ec-gs76.4b72e41/dkms.conf"
verifie "succès : commit figé demandé à git" grep -q '4b72e41bdeb6d0c9949dd3b16a5dff1a6956ff97' "$RACINE/journal"
verifie "succès : règle udev écrite" grep -q 'chgrp msi-ec' "$RACINE/etc/udev/rules.d/99-msi-ec.rules"
verifie "succès : seuil 80 par défaut" grep -q 'echo 80 ' "$RACINE/etc/udev/rules.d/99-msi-ec.rules"
verifie "succès : règle sans RACINE" bash -c '! grep -q "$1" "$2"' _ "$RACINE" "$RACINE/etc/udev/rules.d/99-msi-ec.rules"
verifie "succès : groupadd msi-ec" grep -q '^groupadd msi-ec' "$RACINE/journal"
verifie "succès : usermod -aG msi-ec alice" grep -q '^usermod -aG msi-ec alice' "$RACINE/journal"
verifie "succès : demande de se reconnecter" grep -qi 'reconnect' "$RACINE/sortie"
verifie "succès : pilote précédent mémorisé" grep -qx 'r734.d7fbbd8' "$RACINE/var/lib/msi-gs76-linux/pilote-precedent"

# 3. Deuxième exécution : aucun doublon, précédent inchangé.
faux_cmd dkms 'echo "dkms $*" >>"$RACINE/journal"
[ "$1" = status ] && echo "msi-ec/gs76.4b72e41, 7.2.14-1-omarchy, x86_64: installed"
exit 0'
cp "$RACINE/etc/udev/rules.d/99-msi-ec.rules" "$RACINE/regle-avant"
installer; code=$?
verifie "2e exécution : code 0" test "$code" -eq 0
verifie "2e exécution : règle identique" cmp -s "$RACINE/regle-avant" "$RACINE/etc/udev/rules.d/99-msi-ec.rules"
verifie "2e exécution : une seule ligne" test "$(wc -l <"$RACINE/etc/udev/rules.d/99-msi-ec.rules")" -eq 1
verifie "2e exécution : pilote-precedent inchangé" grep -qx 'r734.d7fbbd8' "$RACINE/var/lib/msi-gs76-linux/pilote-precedent"

# 4. Noyau sans en-têtes : signalé « ignoré ».
preparer "7.2.14-1-omarchy 7.2.15-2-omarchy"
rmdir "$RACINE/usr/lib/modules/7.2.14-1-omarchy/build"
installer; code=$?
verifie "noyau sans build : ignoré signalé" grep -q 'noyau 7.2.14-1-omarchy ignoré' "$RACINE/sortie"
verifie "noyau avec build : installé" grep -q 'dkms install msi-ec/gs76.4b72e41 -k 7.2.15-2-omarchy' "$RACINE/journal"
verifie "noyau sans build : pas installé" bash -c '! grep -q -- "-k 7.2.14-1-omarchy" "$1"' _ "$RACINE/journal"

# 5. Matériel non GS76 : arrêt avant git.
preparer "7.2.14-1-omarchy"
echo "Autre PC" >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "non GS76 : code non nul" test "$code" -ne 0
verifie "non GS76 : git jamais appelé" bash -c '! grep -q "^git" "$1" 2>/dev/null' _ "$RACINE/journal"
verifie "non GS76 : dkms jamais appelé" bash -c '! grep -q "^dkms" "$1" 2>/dev/null' _ "$RACINE/journal"
fin
