#!/usr/bin/env bash
# shellcheck disable=SC1091
# Installe le PSR forcé (--psr) et/ou la fréquence de la dalle selon l'alimentation
# (--frequence). Sans option : les deux.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
PSR=/etc/systemd/system/i915-psr-force.service
SCRIPT=/usr/local/bin/edp-refresh-auto
UNITE=/etc/systemd/user/edp-refresh-auto.service

forcer=()
psr=0
frequence=0
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        --psr) psr=1 ;;
        --frequence) frequence=1 ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done
if [ "$psr" -eq 0 ] && [ "$frequence" -eq 0 ]; then
    psr=1
    frequence=1
fi

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
if [ "$psr" -eq 1 ] && [ ! -d "$RACINE/sys/module/i915" ]; then
    echec "module i915 absent : le PSR forcé ne concerne que les GPU Intel i915."
    exit 1
fi
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

if [ "$psr" -eq 1 ]; then
    sauvegarder "$PSR"
    mkdir -p "$RACINE$(dirname "$PSR")"
    install -m644 "$ici/i915-psr-force.service" "$RACINE$PSR"
    systemctl daemon-reload
    if ! systemctl enable --now i915-psr-force.service; then
        avertir "i915-psr-force n'a pas démarré (debugfs absent ou i915 sans PSR ?) ; il sera réessayé au prochain démarrage."
    fi
    ok "PSR forcé installé."
fi

if [ "$frequence" -eq 1 ]; then
    sauvegarder "$SCRIPT"
    sauvegarder "$UNITE"
    mkdir -p "$RACINE$(dirname "$SCRIPT")" "$RACINE$(dirname "$UNITE")"
    install -m755 "$ici/edp-refresh-auto" "$RACINE$SCRIPT"
    install -m644 "$ici/edp-refresh-auto.service" "$RACINE$UNITE"
    systemctl daemon-reload
    systemctl --global enable edp-refresh-auto.service
    ok "fréquence selon l'alimentation installée : elle démarre à la prochaine ouverture de session de $utilisateur."
fi
