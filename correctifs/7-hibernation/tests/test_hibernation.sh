#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests du correctif 7 (limites de puissance réappliquées après hibernation).
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

UNITE=/etc/systemd/system/thermald-apres-hibernation.service

preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    faux_cmd id 'echo 0'
    # is-enabled répond selon la présence d'un témoin posé par enable.
    faux_cmd systemctl 'echo "systemctl $*" >>"$RACINE/journal"
case "$1" in
    enable) touch "$RACINE/active" ;;
    disable) rm -f "$RACINE/active" ;;
    is-enabled) [ -e "$RACINE/active" ] && echo enabled || { echo disabled; exit 1; } ;;
esac'
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }
desinstaller() { bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; }
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

# L'unité elle-même : déclenchée après les trois cibles d'hibernation, relance thermald s'il tourne.
u="$corr/thermald-apres-hibernation.service"
for cible in hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do
    verifie "unité : After contient $cible" grep -qE "^After=.*\\b$cible\\b" "$u"
    verifie "unité : WantedBy contient $cible" grep -qE "^WantedBy=.*\\b$cible\\b" "$u"
done
verifie "unité : relance conditionnelle de thermald" grep -qx 'ExecStart=/usr/bin/systemctl try-restart thermald.service' "$u"
verifie "unité : oneshot" grep -qx 'Type=oneshot' "$u"
verifie "unité : pas liée à la veille simple" bash -c "! grep -qE '\\bsuspend\\.target\\b' '$u'"

preparer
verifier; code=$?
verifie "avant installation : code 1" test "$code" -eq 1
verifie "avant installation : ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

installer; code=$?
verifie "installation : code 0" test "$code" -eq 0
verifie "installation : unité présente et identique" cmp -s "$u" "$RACINE$UNITE"
verifie "installation : daemon-reload appelé" grep -q '^systemctl daemon-reload' "$RACINE/journal"
verifie "installation : unité activée" grep -q '^systemctl enable thermald-apres-hibernation.service' "$RACINE/journal"
verifie "installation : thermald non relancé" bash -c "! grep -q 'restart' '$RACINE/journal'"
verifie "installation : sortie du verifier.sh affichée" grep -q '^OK ' "$RACINE/sortie"
verifier; code=$?
verifie "après installation : code 0" test "$code" -eq 0

installer; code=$?
verifie "seconde installation : code 0" test "$code" -eq 0
verifie "seconde installation : toujours identique" cmp -s "$u" "$RACINE$UNITE"

echo "[Service]" >"$RACINE$UNITE"
verifier; code=$?
verifie "unité modifiée : code 2" test "$code" -eq 2
verifie "unité modifiée : DÉFAUT" grep -q '^DÉFAUT ' "$RACINE/sortie"

preparer
installer
rm -f "$RACINE/active"
verifier; code=$?
verifie "unité présente mais désactivée : code 2" test "$code" -eq 2
verifie "unité désactivée : DÉFAUT" grep -q '^DÉFAUT .*activ' "$RACINE/sortie"

preparer
installer
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "désinstallation : unité désactivée" grep -q '^systemctl disable thermald-apres-hibernation.service' "$RACINE/journal"
verifie "désinstallation : unité retirée" test ! -e "$RACINE$UNITE"
verifie "désinstallation : daemon-reload appelé" grep -q '^systemctl daemon-reload' "$RACINE/journal"
verifier; code=$?
verifie "après désinstallation : code 1" test "$code" -eq 1

# Matériel non reconnu : refus.
preparer
echo Autre >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "matériel inconnu : refus" test "$code" -ne 0
verifie "matériel inconnu : rien installé" test ! -e "$RACINE$UNITE"

fin
