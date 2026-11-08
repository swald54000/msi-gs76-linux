#!/usr/bin/env bash
# Test des outils de test eux-mêmes.
set -u
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/outils.sh
source "$ICI/outils.sh"

# verifie : un échec compté sur « false », aucun sur « true »
echecs=0
verifie "cas volontairement en échec" false >/dev/null
[ "$echecs" -eq 1 ] && ok_attendu=1 || ok_attendu=0
echecs=0
verifie "cas réussi" true >/dev/null
[ "$echecs" -eq 0 ] && ok_attendu_2=1 || ok_attendu_2=0
echecs=0

verifie "verifie compte un échec sur false" test "$ok_attendu" -eq 1
verifie "verifie ne compte rien sur true" test "$ok_attendu_2" -eq 1

# faux_systeme : RACINE temporaire et FAUX_BIN en tête de PATH
faux_systeme
verifie "RACINE est un dossier" test -d "$RACINE"
verifie "FAUX_BIN est en tête de PATH" test "${PATH%%:*}" = "$FAUX_BIN"

# faux_cmd : écrit un exécutable utilisable
faux_cmd dkms 'echo faux'
verifie "faux dkms affiche faux" test "$(dkms)" = "faux"

fin
