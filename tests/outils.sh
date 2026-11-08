#!/usr/bin/env bash
# Outils communs aux tests : à sourcer depuis chaque tests/test_*.sh.
# shellcheck shell=bash

echecs=0
_PATH_ORIGINE="$PATH"
_DOSSIERS_TEMP=()

_nettoyer_temp() {
    local d
    for d in "${_DOSSIERS_TEMP[@]}"; do
        rm -rf "$d"
    done
}
trap _nettoyer_temp EXIT

# Crée un faux système : $RACINE temporaire et $FAUX_BIN en tête de PATH.
faux_systeme() {
    RACINE="$(mktemp -d)"
    FAUX_BIN="$RACINE/faux-bin"
    mkdir -p "$FAUX_BIN"
    _DOSSIERS_TEMP+=("$RACINE")
    export RACINE FAUX_BIN
    PATH="$FAUX_BIN:$_PATH_ORIGINE"
    export PATH
}

# faux_cmd <nom> <script> : écrit un faux exécutable dans $FAUX_BIN.
faux_cmd() {
    local nom="$1" script="$2"
    printf '#!/bin/bash\n%s\n' "$script" >"$FAUX_BIN/$nom"
    chmod +x "$FAUX_BIN/$nom"
}

# verifie <description> <commande…> : affiche « ok » ou « FAIL ».
verifie() {
    local description="$1"
    shift
    if "$@"; then
        echo "ok   $description"
    else
        echo "FAIL $description"
        echecs=$((echecs + 1))
    fi
}

# Termine avec le nombre d'échecs comme code de sortie.
fin() {
    exit "$echecs"
}
