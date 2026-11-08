#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests du correctif 4 (cache batterie et rafraîchissement en tâche de fond).
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

CONF=/etc/msi-gs76-linux/batterie.conf
TMPF=/etc/tmpfiles.d/battery-cache.conf
TIMER=/etc/systemd/system/battery-refresh.timer
SERVICE=/etc/systemd/system/battery-refresh.service
SCRIPT=/usr/local/bin/battery-refresh
CACHE=/sys/module/battery/parameters/cache_time

preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id" "$RACINE/sys/module/battery/parameters"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    echo 1000 >"$RACINE$CACHE"
    mkdir -p "$RACINE/sys/class/power_supply/BAT0"
    echo Battery >"$RACINE/sys/class/power_supply/BAT0/type"
    faux_cmd id 'echo 0'
    faux_cmd systemctl 'echo "systemctl $*" >>"$RACINE/journal"
case "$*" in
"enable --now battery-refresh.timer") touch "$RACINE/timer-actif" ;;
"disable --now battery-refresh.timer") rm -f "$RACINE/timer-actif" ;;
"is-enabled battery-refresh.timer") [ -e "$RACINE/timer-actif" ] ;;
esac'
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }
desinstaller() { bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; }
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

preparer
verifier; code=$?
verifie "avant installation : code 1" test "$code" -eq 1
verifie "avant installation : ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

installer; code=$?
verifie "installation : code 0" test "$code" -eq 0
verifie "installation : batterie.conf contient BAT0" grep -qx 'BATTERIE=/sys/class/power_supply/BAT0' "$RACINE$CONF"
verifie "installation : conf sans préfixe RACINE" test "$(grep -c "$RACINE" "$RACINE$CONF")" -eq 0
verifie "installation : tmpfiles contient 300000" grep -q '300000' "$RACINE$TMPF"
verifie "installation : minuteur 30 s" grep -qx 'OnUnitActiveSec=30s' "$RACINE$TIMER"
verifie "installation : service installé" test -f "$RACINE$SERVICE"
verifie "installation : script exécutable" test -x "$RACINE$SCRIPT"
verifie "installation : cache_time appliqué" test "$(cat "$RACINE$CACHE")" = 300000
verifie "installation : minuteur activé" grep -q '^systemctl enable --now battery-refresh.timer' "$RACINE/journal"
verifier; code=$?
verifie "après installation : code 0" test "$code" -eq 0
verifie "après installation : OK" grep -q '^OK ' "$RACINE/sortie"

installer; code=$?
verifie "seconde installation : code 0" test "$code" -eq 0
verifie "seconde installation : une seule ligne BATTERIE" test "$(grep -c '^BATTERIE=' "$RACINE$CONF")" -eq 1
verifie "seconde installation : un seul OnUnitActiveSec" test "$(grep -c '^OnUnitActiveSec=' "$RACINE$TIMER")" -eq 1
verifie "seconde installation : tmpfiles sur une ligne" test "$(wc -l <"$RACINE$TMPF")" -eq 1

echo 1000 >"$RACINE$CACHE"
verifier; code=$?
verifie "cache_time différent : code 2" test "$code" -eq 2
verifie "cache_time différent : DÉFAUT" grep -q '^DÉFAUT ' "$RACINE/sortie"

# Variables.
preparer
RAFRAICHISSEMENT=60 CACHE_BATTERIE_MS=120000 installer; code=$?
verifie "RAFRAICHISSEMENT=60 : code 0" test "$code" -eq 0
verifie "RAFRAICHISSEMENT=60 : minuteur 60 s" grep -qx 'OnUnitActiveSec=60s' "$RACINE$TIMER"
verifie "CACHE_BATTERIE_MS=120000 : tmpfiles" grep -q '120000' "$RACINE$TMPF"
verifier; code=$?
verifie "valeurs personnalisées : code 0" test "$code" -eq 0

# Valeurs invalides : refus avant tout changement.
preparer
RAFRAICHISSEMENT=abc installer; code=$?
verifie "RAFRAICHISSEMENT invalide : refus" test "$code" -ne 0
verifie "RAFRAICHISSEMENT invalide : rien installé" test ! -e "$RACINE$SCRIPT"
CACHE_BATTERIE_MS=0 installer; code=$?
verifie "CACHE_BATTERIE_MS=0 : refus" test "$code" -ne 0
CACHE_BATTERIE_MS=-5 installer; code=$?
verifie "CACHE_BATTERIE_MS négatif : refus" test "$code" -ne 0
verifie "valeurs invalides : rien installé" test ! -e "$RACINE$CONF"

# Aucune batterie : refus.
preparer
rm -rf "$RACINE/sys/class/power_supply"
installer; code=$?
verifie "aucune batterie : refus" test "$code" -ne 0
verifie "aucune batterie : rien installé" test ! -e "$RACINE$SCRIPT"

# Désinstallation.
preparer
installer
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "désinstallation : script retiré" test ! -e "$RACINE$SCRIPT"
verifie "désinstallation : service retiré" test ! -e "$RACINE$SERVICE"
verifie "désinstallation : minuteur retiré" test ! -e "$RACINE$TIMER"
verifie "désinstallation : tmpfiles retiré" test ! -e "$RACINE$TMPF"
verifie "désinstallation : conf retirée" test ! -e "$RACINE$CONF"
verifie "désinstallation : dossier de conf retiré" test ! -d "$RACINE/etc/msi-gs76-linux"
verifie "désinstallation : cache_time d'origine remis" test "$(cat "$RACINE$CACHE")" = 1000
verifie "désinstallation : minuteur désactivé" grep -q '^systemctl disable --now battery-refresh.timer' "$RACINE/journal"
verifie "désinstallation : daemon-reload" grep -q '^systemctl daemon-reload' "$RACINE/journal"
verifier; code=$?
verifie "après désinstallation : code 1" test "$code" -eq 1

# Fichier préexistant restauré.
preparer
mkdir -p "$RACINE/etc/tmpfiles.d"
echo "# avant" >"$RACINE$TMPF"
installer
installer
desinstaller
verifie "tmpfiles préexistant restauré" test "$(cat "$RACINE$TMPF")" = "# avant"

# Matériel non reconnu : refus ; --force passe.
preparer
echo Autre >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "matériel inconnu : refus" test "$code" -ne 0
verifie "matériel inconnu : rien installé" test ! -e "$RACINE$SCRIPT"
installer --force; code=$?
verifie "--force : code 0" test "$code" -eq 0

# Installation puis désinstallation sans fichier préexistant : rien ne reste.
preparer
installer
installer
desinstaller
reste="$(find "$RACINE" -type f -not -path "$RACINE/faux-bin/*" -not -path "$RACINE/sys/*" -not -path "$RACINE/var/lib/*" -not -name sortie -not -name journal -not -name timer-actif)"
verifie "installer deux fois puis désinstaller : aucun fichier résiduel (hors sauvegardes)" test -z "$reste"

# Borne haute de CACHE_BATTERIE_MS.
preparer
CACHE_BATTERIE_MS=3600001 installer; code=$?
verifie "CACHE_BATTERIE_MS trop grand : refus" test "$code" -ne 0
CACHE_BATTERIE_MS=99999999999 installer; code=$?
verifie "CACHE_BATTERIE_MS énorme : refus" test "$code" -ne 0
verifie "bornes : rien installé" test ! -e "$RACINE$CONF"
CACHE_BATTERIE_MS=3600000 installer; code=$?
verifie "CACHE_BATTERIE_MS=3600000 : accepté" test "$code" -eq 0

# Le script : rétablit la cible configurée, lit la conf sans l'exécuter.
preparer
mkdir -p "$RACINE/sys/class/power_supply/BAT0"
echo Charging >"$RACINE/sys/class/power_supply/BAT0/status"
printf 'BATTERIE=/sys/class/power_supply/BAT0\nCACHE_BATTERIE_MS=300000\n' >"$RACINE/essai.conf"
lancer_script() { BATTERIE_CONF="$1" CACHE_BATTERIE_PARAM="$RACINE$CACHE" BATTERIE_RACINE="$RACINE" bash "$corr/battery-refresh" 2>/dev/null; }
echo 1000 >"$RACINE$CACHE"
lancer_script "$RACINE/essai.conf"; code=$?
verifie "battery-refresh : code 0" test "$code" -eq 0
verifie "battery-refresh : cible configurée rétablie" test "$(cat "$RACINE$CACHE")" = 300000
echo 1 >"$RACINE$CACHE"
lancer_script "$RACINE/essai.conf"
verifie "battery-refresh : cache_time resté à 1 → cible rétablie" test "$(cat "$RACINE$CACHE")" = 300000

echo 1234 >"$RACINE$CACHE"
lancer_script "$RACINE/absente.conf"; code=$?
verifie "conf absente : code 1" test "$code" -eq 1
verifie "conf absente : cache_time inchangé" test "$(cat "$RACINE$CACHE")" = 1234
echo "n'importe quoi" >"$RACINE/mauvaise.conf"
lancer_script "$RACINE/mauvaise.conf"; code=$?
verifie "conf mal formée : code 1" test "$code" -eq 1
verifie "conf mal formée : cache_time inchangé" test "$(cat "$RACINE$CACHE")" = 1234
printf 'BATTERIE=/tmp/../etc\nCACHE_BATTERIE_MS=300000\n' >"$RACINE/chemin.conf"
lancer_script "$RACINE/chemin.conf"; code=$?
verifie "chemin hors power_supply : code 1" test "$code" -eq 1
verifie "chemin invalide : cache_time inchangé" test "$(cat "$RACINE$CACHE")" = 1234
printf 'BATTERIE=/sys/class/power_supply/BAT0\nCACHE_BATTERIE_MS=abc\n' >"$RACINE/cache.conf"
lancer_script "$RACINE/cache.conf"; code=$?
verifie "cache invalide : code 1" test "$code" -eq 1
printf 'BATTERIE=/sys/class/power_supply/BAT0\nCACHE_BATTERIE_MS=300000\ntouch %s/pwn\n' "$RACINE" >"$RACINE/piege.conf"
lancer_script "$RACINE/piege.conf"
verifie "conf non exécutée" test ! -e "$RACINE/pwn"

fin
