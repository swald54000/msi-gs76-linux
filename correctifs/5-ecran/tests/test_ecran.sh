#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests du correctif 5 (fréquence de l'écran selon l'alimentation).
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

PSR=/etc/systemd/system/i915-psr-force.service
SCRIPT=/usr/local/bin/edp-refresh-auto
UNITE=/etc/systemd/user/edp-refresh-auto.service
LIEN=/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service

# preparer [version hyprctl] : "-" pour un hyprctl en panne, "" pour aucun.
preparer() {
    faux_systeme
    export SUDO_USER=alice
    mkdir -p "$RACINE/sys/class/dmi/id" "$RACINE/sys/module/i915"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.10C" >"$RACINE/sys/class/dmi/id/bios_version"
    faux_cmd id 'echo 0'
    faux_cmd systemctl 'echo "systemctl $*" >>"$RACINE/journal"
case "$*" in
"enable --now i915-psr-force.service") touch "$RACINE/psr-actif" ;;
"disable --now i915-psr-force.service") rm -f "$RACINE/psr-actif" ;;
"is-active i915-psr-force"*) [ -e "$RACINE/psr-actif" ] ;;
"--global enable edp-refresh-auto.service")
    [ "${ENABLE_ECHEC:-0}" = 1 ] && exit 1
    mkdir -p "$RACINE/etc/systemd/user/graphical-session.target.wants"
    ln -sf ../edp-refresh-auto.service "$RACINE/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service" ;;
"--global is-enabled edp-refresh-auto.service")
    [ -L "$RACINE/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service" ] ;;
"--global disable edp-refresh-auto.service")
    rm -f "$RACINE/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service" ;;
esac'
    version_hyprland "${1-0.56.1}"
}
version_hyprland() {
    case "$1" in
        "") rm -f "$FAUX_BIN/hyprctl" ;;
        -) faux_cmd hyprctl 'exit 1' ;;
        *) faux_cmd hyprctl "[ \"\$1\" = version ] && [ \"\$2\" = -j ] && echo '{\"branch\":\"main\",\"tag\":\"v$1\"}'" ;;
    esac
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }
desinstaller() { bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; }
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

# Avant installation.
preparer
verifier; code=$?
verifie "avant installation : code 1" test "$code" -eq 1
verifie "avant installation : ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

# Activation globale en échec : ÉCHEC, code non nul, jamais de message de réussite.
preparer
ENABLE_ECHEC=1 installer; code=$?
verifie "activation en échec : code non nul" test "$code" -ne 0
verifie "activation en échec : ÉCHEC affiché" grep -q '^ÉCHEC .*edp-refresh-auto' "$RACINE/sortie"
verifie "activation en échec : pas de message de réussite" bash -c '! grep -q "^OK fréquence selon l.alimentation installée" "$1"' _ "$RACINE/sortie"

# Sans option : le script et son unité, plus de service PSR (assuré par le correctif 8).
preparer
installer; code=$?
verifie "sans option : code 0" test "$code" -eq 0
verifie "sans option : pas de service PSR" test ! -e "$RACINE$PSR"
verifie "sans option : script installé exécutable" test -x "$RACINE$SCRIPT"
verifie "sans option : unité utilisateur installée" cmp -s "$corr/edp-refresh-auto.service" "$RACINE$UNITE"
verifie "unité utilisateur : chemin absolu du script" grep -q "^ExecStart=$SCRIPT\$" "$RACINE$UNITE"
verifie "sans option : PSR jamais activé" bash -c '! grep -q "i915-psr-force" "$1"' _ "$RACINE/journal"
verifie "sans option : unité activée globalement" grep -q '^systemctl --global enable edp-refresh-auto.service' "$RACINE/journal"
verifie "sans option : lien d'activation créé" test -L "$RACINE$LIEN"
verifie "sans option : sortie du verifier.sh affichée" grep -q '^OK fréquence : unité utilisateur activée' "$RACINE/sortie"
verifie "sans option : prochain démarrage de session annoncé" grep -qi 'prochaine ouverture de session' "$RACINE/sortie"
verifier; code=$?
verifie "après installation : code 0" test "$code" -eq 0
verifie "après installation : ligne OK" grep -q '^OK fréquence : unité utilisateur activée' "$RACINE/sortie"

installer; code=$?
verifie "seconde installation : code 0" test "$code" -eq 0
verifie "seconde installation : script identique" cmp -s "$corr/edp-refresh-auto" "$RACINE$SCRIPT"

# Ancien service de PSR forcé encore installé (version précédente du correctif) : DÉFAUT,
# puis retiré par l'installateur.
mkdir -p "$RACINE/etc/systemd/system"
echo "[Unit]" >"$RACINE$PSR"
verifier; code=$?
verifie "ancien PSR forcé présent : code 2" test "$code" -eq 2
verifie "ancien PSR forcé présent : DÉFAUT qui renvoie au correctif 8" grep -q '^DÉFAUT .*i915-psr-force.*correctif 8' "$RACINE/sortie"
: >"$RACINE/journal"
installer; code=$?
verifie "réinstallation : code 0" test "$code" -eq 0
verifie "réinstallation : ancien service retiré" test ! -e "$RACINE$PSR"
verifie "réinstallation : ancien service désactivé" grep -q '^systemctl disable --now i915-psr-force.service' "$RACINE/journal"
verifie "réinstallation : retrait annoncé" grep -q 'i915-psr-force' "$RACINE/sortie"
verifier; code=$?
verifie "après retrait de l'ancien service : code 0" test "$code" -eq 0
rm -f "$RACINE$LIEN"
verifier; code=$?
verifie "unité non activée : code 2" test "$code" -eq 2

# Désinstallation.
preparer
installer
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "désinstallation : script retiré" test ! -e "$RACINE$SCRIPT"
verifie "désinstallation : unité utilisateur retirée" test ! -e "$RACINE$UNITE"
verifie "désinstallation : lien retiré" test ! -e "$RACINE$LIEN"
verifie "désinstallation : aucun appel sur le PSR quand l'ancien service est absent" bash -c '! grep -q "i915-psr-force" "$1"' _ "$RACINE/journal"
verifie "désinstallation : unité globale désactivée" grep -q '^systemctl --global disable edp-refresh-auto.service' "$RACINE/journal"
verifie "désinstallation : daemon-reload" grep -q '^systemctl daemon-reload' "$RACINE/journal"
verifier; code=$?
verifie "après désinstallation : code 1" test "$code" -eq 1

# Unité déjà supprimée à la main : le lien d'activation est quand même retiré.
preparer
installer
rm -f "$RACINE$UNITE"
desinstaller; code=$?
verifie "unité supprimée avant : code 0" test "$code" -eq 0
verifie "unité supprimée avant : lien retiré" test ! -L "$RACINE$LIEN"

# Deux installations puis désinstallation, sans fichier préexistant : rien ne reste.
preparer
installer
installer
desinstaller
reste="$(find "$RACINE" -type f -not -path "$RACINE/faux-bin/*" -not -path "$RACINE/sys/*" -not -path "$RACINE/var/lib/*" -not -name sortie -not -name journal -not -name psr-actif)"
verifie "installer deux fois puis désinstaller : aucun fichier résiduel (hors sauvegardes)" test -z "$reste"
verifie "installer deux fois puis désinstaller : aucun lien résiduel" test -z "$(find "$RACINE/etc" -type l 2>/dev/null)"

# Désinstallation avec l'ancien service de PSR forcé encore présent : retiré aussi.
preparer
installer
mkdir -p "$RACINE/etc/systemd/system"
echo "[Unit]" >"$RACINE$PSR"
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation avec ancien PSR : code 0" test "$code" -eq 0
verifie "désinstallation avec ancien PSR : service retiré" test ! -e "$RACINE$PSR"
verifie "désinstallation avec ancien PSR : service désactivé" grep -q '^systemctl disable --now i915-psr-force.service' "$RACINE/journal"

# --psr n'existe plus : refus qui renvoie au correctif 8, rien d'installé.
preparer
installer --psr; code=$?
verifie "--psr : refus" test "$code" -ne 0
verifie "--psr : renvoie au correctif 8" grep -q '^ÉCHEC .*correctif 8' "$RACINE/sortie"
verifie "--psr : rien installé" test ! -e "$RACINE$SCRIPT" -a ! -e "$RACINE$PSR"

# Le module i915 n'est plus exigé : la bascule de fréquence passe par le compositeur.
preparer
rmdir "$RACINE/sys/module/i915"
installer; code=$?
verifie "sans module i915 : accepté" test "$code" -eq 0

# --frequence selon la version de Hyprland.
preparer 0.55.0
installer --frequence; code=$?
verifie "--frequence Hyprland 0.55.0 : refus" test "$code" -ne 0
verifie "--frequence 0.55.0 : rien installé" test ! -e "$RACINE$SCRIPT"
installer --frequence --force; code=$?
verifie "--frequence 0.55.0 --force : accepté" test "$code" -eq 0
preparer 0.56.1
installer --frequence; code=$?
verifie "--frequence Hyprland 0.56.1 : accepté" test "$code" -eq 0
verifie "--frequence 0.56.1 : script installé" test -x "$RACINE$SCRIPT"
verifie "--frequence : pas de service PSR" test ! -e "$RACINE$PSR"
verifier; code=$?
verifie "--frequence : vérification 0" test "$code" -eq 0
preparer 1.0.0
installer --frequence; code=$?
verifie "--frequence Hyprland 1.0.0 : accepté" test "$code" -eq 0

# hyprctl en panne : repli sur pacman.
preparer -
faux_cmd pacman '[ "$1 $2" = "-Q hyprland" ] && echo "hyprland 0.56.1-1"'
installer --frequence; code=$?
verifie "hyprctl en panne, pacman 0.56.1 : accepté" test "$code" -eq 0
preparer -
faux_cmd pacman '[ "$1 $2" = "-Q hyprland" ] && echo "hyprland 0.54.2-1"'
installer --frequence; code=$?
verifie "hyprctl en panne, pacman 0.54.2 : refus" test "$code" -ne 0
# Aucune source de version.
preparer -
faux_cmd pacman 'exit 1'
installer --frequence; code=$?
verifie "version introuvable : refus" test "$code" -ne 0
verifie "version introuvable : message clair" grep -q 'Hyprland' "$RACINE/sortie"
installer --frequence --force; code=$?
verifie "version introuvable --force : accepté" test "$code" -eq 0

# Matériel non reconnu et option inconnue.
preparer
echo Autre >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "matériel inconnu : refus" test "$code" -ne 0
verifie "matériel inconnu : rien installé" test ! -e "$RACINE$SCRIPT"
installer --bidon; code=$?
verifie "option inconnue : refus" test "$code" -ne 0

fin
