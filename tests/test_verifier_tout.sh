#!/usr/bin/env bash
# shellcheck disable=SC1091
# Tests de verifier-tout.sh : faux verifier.sh via VERIFIER_DOSSIER.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
depot="$ici/.."
. "$ici/outils.sh"

# preparer <code>… : un faux correctif par code, numéroté à partir de 1.
preparer() {
    faux_systeme
    export VERIFIER_DOSSIER="$RACINE/correctifs"
    local n=0 code
    for code in "$@"; do
        n=$((n + 1))
        mkdir -p "$VERIFIER_DOSSIER/$n-faux"
        printf '#!/bin/bash\necho "INFO préambule %s"\n[ %s -eq 2 ] && echo "DÉFAUT problème %s"\necho "OK détail %s"\nexit %s\n' \
            "$n" "$code" "$n" "$n" "$code" >"$VERIFIER_DOSSIER/$n-faux/verifier.sh"
    done
}
lancer() { bash "$depot/verifier-tout.sh" >"$RACINE/sortie" 2>&1; }

preparer 0 1 0 1 0 0
lancer; code=$?
verifie "aucun défaut : code 0" test "$code" -eq 0
verifie "deux lignes non installé" test "$(grep -c 'non installé' "$RACINE/sortie")" -eq 2
verifie "quatre lignes sain" test "$(grep -c 'sain' "$RACINE/sortie")" -eq 4
verifie "en-tête du tableau" grep -q 'correctif.*état.*détail' "$RACINE/sortie"

preparer 0 1 2 0 0 0
lancer; code=$?
verifie "un défaut : code 1" test "$code" -eq 1
verifie "ligne en défaut" grep -q 'en défaut' "$RACINE/sortie"
verifie "détail = ligne DÉFAUT" grep -q 'DÉFAUT problème 3' "$RACINE/sortie"
verifie "ne s'arrête pas au défaut" grep -q '6-faux' "$RACINE/sortie"

preparer 0 7
lancer; code=$?
verifie "code inattendu : en défaut, code 1" test "$code" -eq 1
verifie "code inattendu affiché en défaut" grep -q '2-faux.*en défaut' "$RACINE/sortie"
fin
