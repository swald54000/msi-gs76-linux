#!/usr/bin/env bash
# Tests de lib/commun.sh
# SC2016 : les scripts des faux exécutables sont volontairement en apostrophes.
# SC2329 : contient/echoue sont appelées indirectement via verifie.
# shellcheck disable=SC2016,SC2329
set -u
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/outils.sh
source "$ICI/outils.sh"

# Écrit une valeur DMI dans le faux système
dmi() { # dmi <champ> <valeur>
    mkdir -p "$RACINE/sys/class/dmi/id"
    printf '%s\n' "$2" >"$RACINE/sys/class/dmi/id/$1"
}
# Écrit le fw_version de msi-ec
fw() {
    mkdir -p "$RACINE/sys/devices/platform/msi-ec"
    printf '%s\n' "$1" >"$RACINE/sys/devices/platform/msi-ec/fw_version"
}
# Crée une alimentation : alim <nom> <type> [scope]
alim() {
    local d="$RACINE/sys/class/power_supply/$1"
    mkdir -p "$d"
    printf '%s\n' "$2" >"$d/type"
    [ -n "${3:-}" ] && printf '%s\n' "$3" >"$d/scope"
    return 0
}
contient() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
echoue() { ! "$@"; }

# --- Matériel ---
faux_systeme
# shellcheck source=lib/commun.sh
source "$ICI/../lib/commun.sh"

dmi product_name "GS76 Stealth 11UH"; fw "17M1EMS1.113"
verifier_materiel >/dev/null 2>&1
verifie "GS76 + fw 17M1 accepté" test $? -eq 0

faux_systeme; dmi product_name "GS66 Stealth"; fw "16V4EMS1.100"
sortie="$(verifier_materiel 2>&1)"; code=$?
verifie "GS66 refusé" test "$code" -eq 1
verifie "message cite GS66" contient "$sortie" "GS66"

faux_systeme; dmi product_name "GS76 Stealth 11UH"; dmi bios_version "E17M1IMS.119"
verifier_materiel >/dev/null 2>&1
verifie "GS76 sans msi-ec, BIOS E17M1 accepté" test $? -eq 0

faux_systeme; dmi product_name "GS76 Stealth 11UH"; dmi bios_version "E1542IMS.10A"
sortie="$(verifier_materiel 2>&1)"; code=$?
verifie "GS76 avec BIOS E1542 refusé" test "$code" -eq 1
verifie "message cite le BIOS lu" contient "$sortie" "E1542IMS.10A"

faux_systeme; dmi product_name "GS66 Stealth"
sortie="$(verifier_materiel --force 2>&1)"; code=$?
verifie "--force accepte un autre modèle" test "$code" -eq 0
verifie "--force avertit (ATTENTION)" contient "$sortie" "ATTENTION"

# --- Utilisateur cible ---
SUDO_USER="" verifie "SUDO_USER vide refusé" echoue utilisateur_cible 2>/dev/null
SUDO_USER=root verifie "SUDO_USER=root refusé" echoue utilisateur_cible 2>/dev/null
SUDO_USER=alice
verifie "SUDO_USER=alice affiché" test "$(utilisateur_cible)" = "alice"
unset SUDO_USER

# --- Batterie ---
faux_systeme
alim AC Mains; alim hidpp_battery_0 Battery Device; alim BAT0 Battery System
verifie "batterie ignore AC et périphérique" test "$(batterie)" = "$RACINE/sys/class/power_supply/BAT0"

faux_systeme; alim AC Mains; alim BAT0 Battery
verifie "batterie sans fichier scope acceptée" test "$(batterie)" = "$RACINE/sys/class/power_supply/BAT0"

faux_systeme; alim AC Mains
verifie "aucune batterie : retour 1" echoue batterie

# --- Sauvegardes ---
faux_systeme
mkdir -p "$RACINE/etc"
echo origine >"$RACINE/etc/x"
sauvegarder /etc/x
echo modifie >"$RACINE/etc/x"
sauvegarder /etc/x
verifie "la sauvegarde garde l'original" test "$(cat "$RACINE/var/lib/msi-gs76-linux/sauvegardes/etc/x")" = "origine"
restaurer /etc/x
verifie "restaurer remet l'original" test "$(cat "$RACINE/etc/x")" = "origine"

echo cree >"$RACINE/etc/y"
restaurer /etc/y
verifie "restaurer sans sauvegarde supprime le fichier" test ! -e "$RACINE/etc/y"

faux_systeme
mkdir -p "$RACINE/etc"
sauvegarder /etc/z
echo installe >"$RACINE/etc/z"
sauvegarder /etc/z
restaurer /etc/z
verifie "fichier absent à l'origine : supprimé après restaurer" test ! -e "$RACINE/etc/z"
verifie "marqueur .absent retiré" test ! -e "$RACINE/var/lib/msi-gs76-linux/sauvegardes/etc/z.absent"

# --- Initramfs ---
faux_systeme
faux_cmd mkinitcpio 'echo "$@" >>"$RACINE/journal"'
PATH_ORIGINE="$PATH"; PATH="$FAUX_BIN"
reconstruire_initramfs >/dev/null 2>&1
PATH="$PATH_ORIGINE"
verifie "mkinitcpio -P appelé sans limine" test "$(cat "$RACINE/journal")" = "-P"

faux_systeme
faux_cmd mkinitcpio 'echo mkinitcpio >>"$RACINE/journal"'
faux_cmd limine-mkinitcpio 'echo limine >>"$RACINE/journal"'
reconstruire_initramfs >/dev/null 2>&1
verifie "limine-mkinitcpio préféré" test "$(cat "$RACINE/journal")" = "limine"

# --- Instantané ---
faux_systeme
faux_cmd snapper 'echo "$@" >>"$RACINE/journal"'
instantane "avant test" >/dev/null 2>&1
verifie "snapper appelé avec la description" test "$(cat "$RACINE/journal")" = "-c root create -d avant test"

# --- Root ---
faux_systeme
faux_cmd id 'echo 1000'
sortie="$( (exiger_root) 2>&1)"; code=$?
verifie "exiger_root refuse un non-root" test "$code" -eq 1
faux_cmd id 'echo 0'
verifie "exiger_root accepte root" exiger_root

fin
