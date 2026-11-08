#!/usr/bin/env bash
# Vérification d'ensemble : lance le verifier.sh de chaque correctif et affiche
# un tableau « correctif | état | détail ». Sans privilèges, ne s'arrête jamais
# au premier échec. Code 0 si aucun correctif n'est en défaut, sinon 1.
# VERIFIER_DOSSIER (tests) remplace le dossier correctifs/.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dossier="${VERIFIER_DOSSIER:-$ici/correctifs}"

lignes=()
defauts=0
for script in "$dossier"/*/verifier.sh; do
    [ -f "$script" ] || continue
    nom="$(basename "$(dirname "$script")")"
    sortie="$(bash "$script" 2>&1)"
    code=$?
    case "$code" in
        0) etat="sain" ;;
        1) etat="non installé" ;;
        *) etat="en défaut"; defauts=$((defauts + 1)) ;;
    esac
    detail="$(printf '%s\n' "$sortie" | grep -m1 '^DÉFAUT' || true)"
    [ -n "$detail" ] || detail="$(printf '%s\n' "$sortie" | head -n 1)"
    lignes+=("$nom|$etat|$detail")
done

{
    echo "correctif|état|détail"
    printf '%s\n' "${lignes[@]}"
} | column -t -s '|'

[ "$defauts" -eq 0 ]
