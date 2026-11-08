#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests du correctif 2 (SSDT) : installation, désinstallation, vérification, table versionnée.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

AML=/etc/initcpio/acpi_override/ssdt-gs76.aml
CONF=/etc/mkinitcpio.conf.d/zz-acpi-override.conf

preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    faux_cmd id 'echo 0'
    faux_cmd snapper 'echo "snapper $*" >>"$RACINE/journal"'
    faux_cmd limine-mkinitcpio 'echo "limine-mkinitcpio" >>"$RACINE/journal"'
    faux_cmd mkinitcpio 'echo "mkinitcpio $*" >>"$RACINE/journal"'
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }
desinstaller() { bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; }
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }
nb_reconstructions() { { cat "$RACINE/journal" 2>/dev/null || true; } | grep -c -e '^limine-mkinitcpio' -e '^mkinitcpio' || true; }

# --- Installation -----------------------------------------------------------
preparer
installer; code=$?
verifie "installation : code 0" test "$code" -eq 0
verifie "installation : table installée" cmp -s "$corr/ssdt-gs76.aml" "$RACINE$AML"
verifie "installation : conf présente avec le contenu exact" test "$(cat "$RACINE$CONF")" = 'HOOKS+=(acpi_override)'
verifie "installation : limine-mkinitcpio appelé" grep -q '^limine-mkinitcpio' "$RACINE/journal"
verifie "installation : instantané demandé" grep -q '^snapper ' "$RACINE/journal"

# Sans limine-mkinitcpio : repli sur mkinitcpio -P. PATH réduit aux outils système
# (liens symboliques) moins limine-mkinitcpio, qui peut exister sur la machine de test.
preparer
mkdir -p "$RACINE/bin-sans-limine"
for f in /usr/bin/*; do
    [ "$(basename "$f")" = limine-mkinitcpio ] || ln -s "$f" "$RACINE/bin-sans-limine/$(basename "$f")"
done
rm -f "$FAUX_BIN/limine-mkinitcpio"
PATH="$FAUX_BIN:$RACINE/bin-sans-limine" installer; code=$?
verifie "repli : code 0" test "$code" -eq 0
verifie "repli : mkinitcpio -P appelé" grep -q '^mkinitcpio -P' "$RACINE/journal"
verifie "repli : limine-mkinitcpio non appelé" bash -c '! grep -q "^limine-mkinitcpio" "$1"' _ "$RACINE/journal"

# Deux installations : une seule ligne.
preparer
installer
installer; code=$?
verifie "deux installations : code 0" test "$code" -eq 0
verifie "deux installations : une seule ligne dans la conf" test "$(wc -l <"$RACINE$CONF")" -eq 1
verifie "deux installations : reconstruit à chaque fois" test "$(nb_reconstructions)" -eq 2

# Ancienne DSDT complète : refus sans rien reconstruire.
preparer
mkdir -p "$RACINE/etc/initcpio/acpi_override"
: >"$RACINE/etc/initcpio/acpi_override/dsdt.aml"
installer; code=$?
verifie "dsdt.aml présent : refus (code ≠ 0)" test "$code" -ne 0
verifie "dsdt.aml présent : aucune reconstruction" test "$(nb_reconstructions)" -eq 0
verifie "dsdt.aml présent : table non installée" test ! -e "$RACINE$AML"
verifie "dsdt.aml présent : conf non créée" test ! -e "$RACINE$CONF"

# Matériel non reconnu : refus, --force passe.
preparer
echo "Autre" >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "matériel inconnu : refus" test "$code" -ne 0
verifie "matériel inconnu : table non installée" test ! -e "$RACINE$AML"
installer --force; code=$?
verifie "--force : installation" test "$code" -eq 0 -a -e "$RACINE$AML"

# --- Désinstallation --------------------------------------------------------
preparer
installer
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "désinstallation : table retirée" test ! -e "$RACINE$AML"
verifie "désinstallation : conf retirée" test ! -e "$RACINE$CONF"
verifie "désinstallation : initramfs reconstruit" grep -q '^limine-mkinitcpio' "$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation répétée : code 0" test "$code" -eq 0

# Une autre table .aml reste : la conf est conservée.
preparer
installer
: >"$RACINE/etc/initcpio/acpi_override/autre.aml"
desinstaller; code=$?
verifie "autre .aml : code 0" test "$code" -eq 0
verifie "autre .aml : notre table retirée" test ! -e "$RACINE$AML"
verifie "autre .aml : conf conservée" test -e "$RACINE$CONF"
verifie "autre .aml : leur table intacte" test -e "$RACINE/etc/initcpio/acpi_override/autre.aml"

# Une conf préexistante différente est restaurée.
preparer
mkdir -p "$RACINE/etc/mkinitcpio.conf.d"
echo '# avant' >"$RACINE$CONF"
installer
desinstaller
verifie "conf préexistante restaurée" test "$(cat "$RACINE$CONF")" = '# avant'

# --- Vérification -----------------------------------------------------------
fausse_table() {
    mkdir -p "$RACINE/sys/firmware/acpi/tables"
    printf 'SSDT\x00GS76FIX\x00' >"$RACINE/sys/firmware/acpi/tables/SSDT7"
}
journal_faux() { # $1 = texte du journal, ou « illisible »
    if [ "$1" = illisible ]; then
        faux_cmd journalctl 'echo "Failed to read journal" >&2; exit 1'
    else
        faux_cmd journalctl "echo '$1'"
    fi
}
profil() { mkdir -p "$RACINE/proc/bus/input"; echo "$1" >"$RACINE/proc/bus/input/devices"; }

preparer
journal_faux illisible
verifier; code=$?
verifie "non installé : code 1" test "$code" -eq 1
verifie "non installé : ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

preparer
installer
fausse_table
journal_faux illisible
profil 'N: Name="Elan Touchpad"'
verifier; code=$?
verifie "table chargée (SSDT lisible) : code 0" test "$code" -eq 0
verifie "table chargée : OK" grep -q '^OK ' "$RACINE/sortie"
verifie "journal illisible : INFO et non DÉFAUT" grep -q '^INFO .*journal' "$RACINE/sortie"
verifie "journal illisible : pas de DÉFAUT" bash -c '! grep -q "^DÉFAUT" "$1"' _ "$RACINE/sortie"

preparer
installer
journal_faux 'kernel: ACPI: SSDT 0x00000000 (v02 GS76FX GS76FIX 00000001 INTL 20251212)'
profil 'N: Name="Elan Touchpad"'
verifier; code=$?
verifie "GS76FIX dans le journal : code 0" test "$code" -eq 0

preparer
installer
journal_faux 'kernel: ACPI: rien de spécial'
profil 'N: Name="Elan Touchpad"'
verifier; code=$?
verifie "journal lisible sans GS76FIX : code 2" test "$code" -eq 2
verifie "journal lisible sans GS76FIX : DÉFAUT" grep -q '^DÉFAUT ' "$RACINE/sortie"

preparer
installer
journal_faux 'kernel: ACPI: SSDT GS76FIX'
profil 'N: Name="SynPS/2 Synaptics TouchPad"'
verifier; code=$?
verifie "SynPS/2 présent : code 2" test "$code" -eq 2
verifie "SynPS/2 présent : DÉFAUT" grep -q '^DÉFAUT .*SynPS/2' "$RACINE/sortie"

preparer
installer
journal_faux illisible
mkdir -p "$RACINE/sys/firmware/acpi/tables"
printf 'SSDT\x00AUTRE\x00' >"$RACINE/sys/firmware/acpi/tables/SSDT7"
verifier; code=$?
verifie "SSDT lisibles sans GS76FIX : code 2" test "$code" -eq 2

preparer
installer
journal_faux illisible
mkdir -p "$RACINE/sys/firmware/acpi/tables"
printf 'SSDT\x00AUTRE\x00' >"$RACINE/sys/firmware/acpi/tables/SSDT7"
chmod 000 "$RACINE/sys/firmware/acpi/tables/SSDT7"
verifier; code=$?
if [ "$EUID" -eq 0 ]; then
    echo "skip SSDT illisibles : lancé en root"
else
    verifie "SSDT illisibles (non root) : code 0 sans preuve contraire" test "$code" -eq 0
fi

# --- Table versionnée -------------------------------------------------------
if command -v iasl >/dev/null 2>&1; then
    temp="$(mktemp -d)"
    _DOSSIERS_TEMP+=("$temp")
    cp "$corr/ssdt-gs76.asl" "$temp/"
    (cd "$temp" && iasl ssdt-gs76.asl >/dev/null 2>&1)
    verifie "aml versionné identique à la compilation de l'asl" cmp -s "$corr/ssdt-gs76.aml" "$temp/ssdt-gs76.aml"
else
    echo "skip comparaison aml/asl : iasl absent"
fi
verifie "aml versionné porte l'identifiant GS76FIX" grep -aq GS76FIX "$corr/ssdt-gs76.aml"

fin
