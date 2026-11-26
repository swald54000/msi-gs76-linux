#!/usr/bin/env bash
# shellcheck disable=SC1091
# Retire le pilote msi-ec installé par le correctif, remet le pilote précédent et la règle udev d'origine.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
GROUPE=msi-ec
fichier_regle=/etc/udev/rules.d/99-msi-ec.rules
fichier_chargement=/etc/modules-load.d/msi-ec.conf
etat="$RACINE/var/lib/msi-gs76-linux"
usrsrc="$RACINE/usr/src"

exiger_root

precedent=""
[ -r "$etat/pilote-precedent" ] && precedent="$(head -n 1 "$etat/pilote-precedent")"

# Retire le module installé par le correctif.
for v in $(dkms status msi-ec 2>/dev/null | sed -n 's|^msi-ec/\([^,]*\),.*|\1|p' | grep '^gs76\.' | sort -u || true); do
    dkms remove "msi-ec/$v" --all || avertir "retrait de msi-ec/$v impossible."
done
rm -rf "$usrsrc"/msi-ec-gs76.*

# Réinstalle la version précédente si ses sources sont encore là.
if [ -n "$precedent" ] && [ -d "$usrsrc/msi-ec-$precedent" ]; then
    info "réinstallation de msi-ec $precedent"
    dkms add "msi-ec/$precedent" 2>/dev/null || true
    for d in "$RACINE"/usr/lib/modules/*/; do
        [ -d "$d" ] || continue
        k="$(basename "$d")"
        if [ -n "${MSI_EC_NOYAUX:-}" ] && [[ " $MSI_EC_NOYAUX " != *" $k "* ]]; then continue; fi
        if [ -d "$d/build" ]; then
            dkms install "msi-ec/$precedent" -k "$k" --force || avertir "installation de $precedent pour $k impossible."
        else
            avertir "noyau $k ignoré : en-têtes absents."
        fi
    done
else
    info "aucune version précédente à réinstaller : le module du correctif est simplement retiré."
fi

# Règle udev : on ne restaure que s'il existe une sauvegarde (ou un marqueur d'absence).
if a_une_sauvegarde "$fichier_regle"; then
    restaurer "$fichier_regle"
else
    avertir "aucune sauvegarde de la règle udev : fichier laissé tel quel."
fi

# Chargement au démarrage : même principe.
if a_une_sauvegarde "$fichier_chargement"; then
    restaurer "$fichier_chargement"
fi

udevadm control --reload
modprobe -r msi_ec 2>/dev/null || true
modprobe msi_ec 2>/dev/null || avertir "msi_ec ne se recharge pas."
udevadm trigger --action=bind --subsystem-match=platform --attr-match=driver=msi-ec || true

# L'utilisateur qui a lancé sudo quitte le groupe (ajouté par l'installateur).
if utilisateur="$(utilisateur_cible 2>/dev/null)"; then
    gpasswd -d "$utilisateur" "$GROUPE" >/dev/null 2>&1 || info "$utilisateur n'était pas membre du groupe $GROUPE."
else
    avertir "utilisateur cible introuvable (SUDO_USER absent) : appartenance au groupe $GROUPE laissée telle quelle."
fi

# Groupe : supprimé seulement s'il n'a plus aucun membre.
ligne="$(getent group "$GROUPE" || true)"
if [ -n "$ligne" ]; then
    membres="${ligne##*:}"
    if [ -z "$membres" ]; then
        groupdel "$GROUPE" || avertir "suppression du groupe $GROUPE impossible."
    else
        info "groupe $GROUPE conservé (membres : $membres)."
    fi
fi

rm -f "$etat/pilote-precedent"
ok "pilote msi-ec du correctif désinstallé."
