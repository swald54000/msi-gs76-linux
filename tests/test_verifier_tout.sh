#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
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
verifie "ligne saine : détail OK, pas l'INFO du préambule" grep -q '1-faux.*sain.*OK détail 1' "$RACINE/sortie"
verifie "aucun préambule INFO dans le tableau" bash -c '! grep -q "INFO" "$1"' _ "$RACINE/sortie"

preparer 0 1 2 0 0 0
lancer; code=$?
verifie "un défaut : code 1" test "$code" -eq 1
verifie "ligne en défaut" grep -q 'en défaut' "$RACINE/sortie"
verifie "détail = ligne DÉFAUT" grep -q 'DÉFAUT problème 3' "$RACINE/sortie"
verifie "ne s'arrête pas au défaut" grep -q '6-faux' "$RACINE/sortie"

# Sans ligne DÉFAUT ni OK : première ligne ABSENT, avant l'INFO suivant.
preparer 1
printf '#!/bin/bash\necho "INFO préambule"\necho "ABSENT rien installé"\necho "INFO fin"\nexit 1\n' >"$VERIFIER_DOSSIER/1-faux/verifier.sh"
lancer
verifie "ligne non installée : détail ABSENT" grep -q '1-faux.*non installé.*ABSENT rien installé' "$RACINE/sortie"
# Aucun préfixe connu : première ligne.
printf '#!/bin/bash\necho "texte libre"\necho "autre"\nexit 1\n' >"$VERIFIER_DOSSIER/1-faux/verifier.sh"
lancer
verifie "sans préfixe connu : première ligne" grep -q '1-faux.*texte libre' "$RACINE/sortie"

preparer 0 7
lancer; code=$?
verifie "code inattendu : en défaut, code 1" test "$code" -eq 1
verifie "code inattendu affiché en défaut" grep -q '2-faux.*en défaut' "$RACINE/sortie"
fin
