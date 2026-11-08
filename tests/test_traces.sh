#!/usr/bin/env bash
# Recherche de traces personnelles dans tout le dépôt (hors .git et ce fichier).
# Motifs interdits : le nom de l'auteur (sauf les jetons publics « swald.fans » et
# « swald54000 »), les chemins personnels, la batterie et l'adresse PCI codées en
# dur, l'ancien groupe d'accès, les adresses e-mail et MAC. Les dumps EC binaires
# ne doivent contenir aucune chaîne ressemblant à un numéro de série.
# Les motifs sont découpés ("a""b") : ce fichier ne se signale pas lui-même.
# SC2329 : vide/contient/absent sont appelées indirectement via verifie.
# shellcheck disable=SC2329
set -u
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/outils.sh
source "$ICI/outils.sh"

MOTIFS_FIXES=("/ho""me/" "Wo""rk/" "BA""T1" "0000:01:00"".0" "game""mode")
# Adresse e-mail : « quelque.chose@domaine.tld »
MOTIF_EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
# Adresse MAC : six octets hexadécimaux séparés par « : »
MOTIF_MAC='([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'
# Identifiant public du firmware EC (offset 0xA0) : version et date de compilation.
MOTIF_FIRMWARE_EC='17M1EMS1\.113[0-9:]*'

# Affiche une occurrence par ligne (fichier:ligne:texte) ; rien si le dossier est propre.
traces_texte() { # dossier
    local dossier="$1" m
    (
        cd "$dossier" || exit 1
        grep -rIniE "sw""ald" --exclude-dir=.git --exclude=test_traces.sh . \
            | sed -E "s/sw""ald\.fans|sw""ald54000//gI" | grep -iE "sw""ald"
        for m in "${MOTIFS_FIXES[@]}"; do
            grep -rInF --exclude-dir=.git --exclude=test_traces.sh -- "$m" .
        done
        grep -rInE --exclude-dir=.git --exclude=test_traces.sh -- "$MOTIF_EMAIL" .
        grep -rInE --exclude-dir=.git --exclude=test_traces.sh -- "$MOTIF_MAC" .
    )
    return 0
}

# Chaînes de 8 caractères imprimables ou plus dans les dumps EC, hors identifiant
# du firmware ; signalées si elles contiennent 8 caractères alphanumériques de
# suite (forme d'un numéro de série). Les octets de courbe forment parfois des
# chaînes courtes comme « 4<AFRXd< », sans suite alphanumérique.
traces_dumps() { # dossier contenant les .bin
    local f
    for f in "$1"/*.bin; do
        [ -f "$f" ] || continue
        strings -n 8 "$f" | sed -E "s/$MOTIF_FIRMWARE_EC//g" \
            | grep -E '[A-Za-z0-9]{8,}' | sed "s|^|$(basename "$f"): |"
    done
    return 0
}

vide() { [ -z "$1" ]; }
contient() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
absent() { ! contient "$1" "$2"; }

# --- Le détecteur trouve chaque motif planté ---------------------------------
faux_systeme
plante="$RACINE/depot"
mkdir -p "$plante/a" "$plante/.git" "$plante/dumps"
{
    echo "utilisateur sw""ald"
    echo "cd /ho""me/quelqu-un"
    echo "cd ~/Wo""rk/projet"
    echo "/sys/class/power_supply/BA""T1"
    echo "gpu 0000:01:00"".0"
    echo "groupe game""mode"
    echo "contact : nom""@exemple.org"
    echo "ether 0a:1b:2c:3d:4e:5f"
} >"$plante/a/sale.sh"
{
    echo "plugin sw""ald.fans"
    echo "https://github.com/sw""ald54000/msi-ec.git"
    echo "horodatage 15:13:31, 50 à 100 %"
} >"$plante/a/propre.md"
echo "sw""ald" >"$plante/.git/ignore"
sortie="$(traces_texte "$plante")"
verifie "détecteur : nom de l'auteur" contient "$sortie" "sale.sh:1:"
verifie "détecteur : chemin personnel" contient "$sortie" "sale.sh:2:"
verifie "détecteur : dossier de travail" contient "$sortie" "sale.sh:3:"
verifie "détecteur : batterie codée en dur" contient "$sortie" "sale.sh:4:"
verifie "détecteur : adresse PCI du GPU" contient "$sortie" "sale.sh:5:"
verifie "détecteur : ancien groupe" contient "$sortie" "sale.sh:6:"
verifie "détecteur : e-mail" contient "$sortie" "sale.sh:7:"
verifie "détecteur : adresse MAC" contient "$sortie" "sale.sh:8:"
verifie "détecteur : jetons publics tolérés" absent "$sortie" "propre.md"
verifie "détecteur : .git ignoré" absent "$sortie" ".git/"

printf '\x00\x01SN0123456789AB\x00\x0217M1EMS1.1130422202215:13:31\x004<AFRXd<\x00' >"$plante/dumps/sale.bin"
printf '\x00\x0117M1EMS1.1130422202215:13:31\x00\x004<AFRXd<\x00' >"$plante/dumps/propre.bin"
sortie="$(traces_dumps "$plante/dumps")"
verifie "détecteur : numéro de série dans un dump" contient "$sortie" "sale.bin: "
verifie "détecteur : firmware et courbe tolérés" absent "$sortie" "propre.bin"

# --- Le dépôt est propre ------------------------------------------------------
sortie="$(traces_texte "$ICI/..")"
[ -n "$sortie" ] && printf '%s\n' "$sortie" | sed 's/^/     /'
verifie "dépôt : aucune trace personnelle dans les fichiers texte" vide "$sortie"

if [ -d "$ICI/../recherche/ec/dumps" ]; then
    sortie="$(traces_dumps "$ICI/../recherche/ec/dumps")"
    [ -n "$sortie" ] && printf '%s\n' "$sortie" | sed 's/^/     /'
    verifie "dépôt : aucun numéro de série dans les dumps EC" vide "$sortie"
else
    echo "FAIL dépôt : recherche/ec/dumps absent"
    echecs=$((echecs + 1))
fi
fin
