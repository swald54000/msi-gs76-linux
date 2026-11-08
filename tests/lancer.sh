#!/usr/bin/env bash
# Lance tous les tests puis shellcheck. Code 0 seulement si tout passe.
set -u
RACINE_DEPOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE_DEPOT" || exit 1

echecs=0

# Tests
for t in tests/test_*.sh correctifs/*/tests/test_*.sh; do
    [ -f "$t" ] || continue
    echo "== $t"
    bash "$t" || echecs=$((echecs + 1))
done

# Bit d'exécution : tout fichier versionné à shebang doit être exécutable
sans_exec=$(git ls-files -s 2>/dev/null | awk '$1 == "100644" {print $4}' | while IFS= read -r f; do
    head -c 2 "$f" 2>/dev/null | grep -q '^#!' && echo "$f"
done)
if [ -n "$sans_exec" ]; then
    echo "FAIL fichiers à shebang sans bit d'exécution :"
    printf '%s\n' "$sans_exec" | sed 's/^/     /'
    echecs=$((echecs + 1))
else
    echo "ok   fichiers à shebang exécutables"
fi

# Outil d'analyse : shellcheck installé, sinon via uvx
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck_cmd=(shellcheck)
elif command -v uvx >/dev/null 2>&1; then
    shellcheck_cmd=(uvx --from shellcheck-py shellcheck)
else
    echo "FAIL shellcheck introuvable (ni shellcheck ni uvx)"
    exit 1
fi

# Cibles : *.sh et fichiers à shebang sh/bash, sous les dossiers connus
cibles=()
for dossier in correctifs lib recherche tests; do
    [ -d "$dossier" ] || continue
    while IFS= read -r -d '' f; do
        case "$f" in
            *.sh) cibles+=("$f") ;;
            *.service | *.conf | *.asl) ;;
            *)
                if head -n 1 "$f" 2>/dev/null | grep -Eq '^#![[:space:]]*((/[^[:space:]]*/)?(ba)?sh|(/[^[:space:]]*/)?env([[:space:]]+-S)?[[:space:]]+(ba)?sh)([[:space:]]|$)'; then
                    cibles+=("$f")
                fi
                ;;
        esac
    done < <(find "$dossier" -type f -print0 | sort -z)
done
[ -f verifier-tout.sh ] && cibles+=(verifier-tout.sh)

echo "== shellcheck (${#cibles[@]} fichiers)"
if [ "${#cibles[@]}" -gt 0 ]; then
    if "${shellcheck_cmd[@]}" -x "${cibles[@]}"; then
        echo "ok   shellcheck"
    else
        echo "FAIL shellcheck"
        echecs=$((echecs + 1))
    fi
fi

exit "$echecs"
