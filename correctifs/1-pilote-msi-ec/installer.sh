#!/usr/bin/env bash
# shellcheck disable=SC1091
# Installe le pilote msi-ec d'origine, à un commit figé, via DKMS, avec la règle udev et le
# groupe msi-ec.
# Variables : MSI_EC_DEPOT, MSI_EC_REF, SEUIL_CHARGE (50 à 100, défaut 80), MSI_EC_NOYAUX.
set -eEuo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
. "$ici/regle-udev.sh"

MSI_EC_DEPOT="${MSI_EC_DEPOT:-https://github.com/MControlSuite/msi-ec.git}"
MSI_EC_REF="${MSI_EC_REF:-c8cbd48ed01f5c4fa7e34ff622a66f5a5380c705}"
GROUPE=msi-ec
RACINE="${RACINE:-}"

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done

# Validation avant toute action.
if ! [[ "$MSI_EC_REF" =~ ^[0-9a-f]{7,40}$ ]]; then
    echec "MSI_EC_REF invalide (« ${MSI_EC_REF} ») : un identifiant de commit en hexadécimal minuscule (7 à 40 caractères) est attendu."
    exit 1
fi
seuil="${SEUIL_CHARGE-80}"
if ! [[ "$seuil" =~ ^[0-9]{2,3}$ ]] || [ "$((10#$seuil))" -lt 50 ] || [ "$((10#$seuil))" -gt 100 ]; then
    echec "SEUIL_CHARGE invalide (« ${seuil} ») : un entier de 50 à 100 est attendu."
    exit 1
fi
seuil="$((10#$seuil))"

exiger_root
verifier_materiel "${forcer[@]}" || exit 1
utilisateur="$(utilisateur_cible)" || exit 1
chemin_bat="$(batterie)" || { echec "aucune batterie détectée dans /sys/class/power_supply."; exit 1; }
nom_bat="$(basename "$chemin_bat")"

version="gs76.${MSI_EC_REF:0:7}"
usrsrc="$RACINE/usr/src"
dest="$usrsrc/msi-ec-$version"
fichier_regle=/etc/udev/rules.d/99-msi-ec.rules
etat="$RACINE/var/lib/msi-gs76-linux"

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

# Récupération du pilote (clone superficiel au commit figé), avant de toucher au système.
info "récupération de $MSI_EC_DEPOT ($MSI_EC_REF)"
git -C "$temp" init -q src
git -C "$temp/src" fetch -q --depth 1 "$MSI_EC_DEPOT" "$MSI_EC_REF"
mkdir -p "$temp/archive"
git -C "$temp/src" archive FETCH_HEAD | tar -x -C "$temp/archive"
[ -f "$temp/archive/dkms.conf" ] || { echec "dkms.conf absent des sources récupérées."; exit 1; }

# Version DKMS déjà présente avant nous (jamais écrasée aux exécutions suivantes).
mkdir -p "$etat"
if [ ! -e "$etat/pilote-precedent" ]; then
    { dkms status msi-ec 2>/dev/null | sed -n 's|^msi-ec/\([^,]*\),.*|\1|p' | grep -v '^gs76\.' | sort -u | head -n 1 || true; } >"$etat/pilote-precedent"
fi
sauvegarder "$fichier_regle"

# À partir d'ici, toute erreur ramène au pilote précédent.
retour() {
    trap - ERR INT TERM
    echec "échec pendant l'installation : retour au pilote précédent."
    bash "$ici/desinstaller.sh" || avertir "le retour arrière a lui aussi échoué."
    exit 1
}
trap retour ERR
trap 'retour' INT TERM

for v in $(dkms status msi-ec 2>/dev/null | sed -n 's|^msi-ec/\([^,]*\),.*|\1|p' | grep '^gs76\.' | sort -u || true); do
    [ "$v" = "$version" ] || dkms remove "msi-ec/$v" --all
done
for d in "$usrsrc"/msi-ec-gs76.*; do
    [ -d "$d" ] && [ "$d" != "$dest" ] && rm -rf "$d"
done
rm -rf "$dest"
mkdir -p "$dest"
cp -a "$temp/archive/." "$dest/"
sed -i "s/@VERSION@/$version/" "$dest/dkms.conf"
dkms add "msi-ec/$version" 2>/dev/null || true

# Noyaux : liste imposée par MSI_EC_NOYAUX, sinon tous ceux de /usr/lib/modules.
noyaux=()
if [ -n "${MSI_EC_NOYAUX:-}" ]; then
    read -r -a noyaux <<<"$MSI_EC_NOYAUX"
else
    for d in "$RACINE"/usr/lib/modules/*/; do
        [ -d "$d" ] && noyaux+=("$(basename "$d")")
    done
fi
installes=0
for k in "${noyaux[@]}"; do
    if [ -d "$RACINE/usr/lib/modules/$k/build" ]; then
        # Un noyau sur lequel le pilote ne se compile pas n'empêche pas les autres.
        if dkms install "msi-ec/$version" -k "$k" --force; then
            installes=$((installes + 1))
        else
            avertir "noyau $k ignoré : le pilote ne s'y compile pas."
        fi
    else
        avertir "noyau $k ignoré : en-têtes absents (installez ses en-têtes puis relancez)."
    fi
done
[ "$installes" -gt 0 ] || { echec "le pilote n'a pu être installé pour aucun noyau."; false; }

# Groupe et utilisateur.
getent group "$GROUPE" >/dev/null || groupadd "$GROUPE"
usermod -aG "$GROUPE" "$utilisateur"

# Règle udev puis rechargement.
mkdir -p "$RACINE$(dirname "$fichier_regle")"
regle_udev "$GROUPE" "$seuil" "$nom_bat" >"$RACINE$fichier_regle"
udevadm control --reload
modprobe -r msi_ec 2>/dev/null || true
modprobe msi_ec
udevadm trigger --action=bind --subsystem-match=platform --attr-match=driver=msi-ec
udevadm settle

[ -e "$RACINE/sys/devices/platform/msi-ec/fan_mode" ] || { echec "le pilote msi-ec n'est pas actif (fan_mode absent)."; false; }

trap - ERR INT TERM
ok "msi-ec $version installé ($installes noyau(x)), seuil de charge $seuil %"
info "vérification (à titre indicatif, sans effet sur le résultat de l'installation) :"
bash "$ici/verifier.sh" || true
info "utilisateur $utilisateur ajouté au groupe $GROUPE : déconnectez-vous puis reconnectez-vous pour que le droit prenne effet."
