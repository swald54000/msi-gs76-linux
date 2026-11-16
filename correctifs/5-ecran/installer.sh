#!/usr/bin/env bash
# shellcheck disable=SC1091
# Installe la fréquence de la dalle selon l'alimentation. Retire aussi l'ancien service de PSR
# forcé : le PSR est désormais assuré par la VBT corrigée du correctif 8.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
PSR=/etc/systemd/system/i915-psr-force.service
SCRIPT=/usr/local/bin/edp-refresh-auto
UNITE=/etc/systemd/user/edp-refresh-auto.service

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        --frequence) ;; # acceptée pour compatibilité : c'est désormais tout le correctif
        --psr)
            echec "l'option --psr n'existe plus : le PSR forcé est remplacé par la VBT corrigée du correctif 8 (correctifs/8-vbt)."
            exit 1 ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done
frequence=1

# Affiche la version (majeure.mineure) de Hyprland, ou rien si introuvable.
version_hyprland() {
    local brut="" v=""
    if command -v hyprctl >/dev/null 2>&1; then
        brut="$(hyprctl version -j 2>/dev/null || true)"
        if [ -n "$brut" ]; then
            if command -v jq >/dev/null 2>&1; then
                v="$(printf '%s' "$brut" | jq -r '.tag // .version // empty' 2>/dev/null || true)"
            else
                v="$(printf '%s' "$brut" | sed -n 's/.*"\(tag\|version\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -n 1)"
            fi
        fi
    fi
    if [ -z "$v" ] && command -v pacman >/dev/null 2>&1; then
        v="$(pacman -Q hyprland 2>/dev/null | awk '{print $2}' || true)"
        v="${v#*:}"
    fi
    v="${v#v}"
    printf '%s\n' "$v" | sed -n 's/^\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p'
}

# Retour 0 si majeure.mineure >= 0.56.
version_suffisante() {
    local maj="${1%%.*}" min="${1#*.}"
    [ "$maj" -gt 0 ] || [ "$min" -ge 56 ]
}

exiger_root
verifier_materiel "${forcer[@]}" || exit 1

# Vérifications préalables, avant tout changement.
if [ "$frequence" -eq 1 ]; then
    utilisateur="$(utilisateur_cible)" || exit 1
    version="$(version_hyprland)"
    if [ -z "$version" ]; then
        if [ "${#forcer[@]}" -eq 0 ]; then
            echec "version de Hyprland introuvable (hyprctl et pacman muets) : ce correctif demande Hyprland 0.56 ou plus. Utilisez --force pour passer outre."
            exit 1
        fi
        avertir "version de Hyprland introuvable : poursuite forcée."
    elif ! version_suffisante "$version"; then
        if [ "${#forcer[@]}" -eq 0 ]; then
            echec "Hyprland $version détecté : ce correctif demande Hyprland 0.56 ou plus. Utilisez --force pour passer outre."
            exit 1
        fi
        avertir "Hyprland $version (< 0.56) : poursuite forcée."
    fi
fi

# Ancien service de PSR forcé (versions précédentes de ce correctif) : retiré, le PSR vient
# maintenant de la VBT corrigée du correctif 8. Son arrêt remet le réglage par défaut du pilote.
if [ -e "$RACINE$PSR" ]; then
    systemctl disable --now i915-psr-force.service || avertir "ancien service i915-psr-force déjà désactivé."
    if a_une_sauvegarde "$PSR"; then
        restaurer "$PSR"
    else
        rm -f "$RACINE$PSR"
    fi
    systemctl daemon-reload
    info "ancien service i915-psr-force retiré : le PSR est assuré par le correctif 8 (VBT corrigée)."
fi

if [ "$frequence" -eq 1 ]; then
    sauvegarder "$SCRIPT"
    sauvegarder "$UNITE"
    mkdir -p "$RACINE$(dirname "$SCRIPT")" "$RACINE$(dirname "$UNITE")"
    install -m755 "$ici/edp-refresh-auto" "$RACINE$SCRIPT"
    install -m644 "$ici/edp-refresh-auto.service" "$RACINE$UNITE"
    systemctl daemon-reload
    if ! systemctl --global enable edp-refresh-auto.service; then
        echec "l'activation de edp-refresh-auto.service a échoué : la fréquence selon l'alimentation ne démarrera pas. Corrigez puis relancez l'installateur."
        exit 1
    fi
    ok "fréquence selon l'alimentation installée."
fi

info "vérification (à titre indicatif, sans effet sur le résultat de l'installation) :"
bash "$ici/verifier.sh" || true
if [ "$frequence" -eq 1 ]; then
    info "la fréquence selon l'alimentation démarre à la prochaine ouverture de session graphique de $utilisateur."
fi
