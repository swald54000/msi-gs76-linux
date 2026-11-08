#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Chronomètre de vraies lectures ACPI de la batterie (_BST)
# en contournant le cache du noyau, puis rétablit le cache.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
BAT="$(batterie)" || { echec "aucune batterie trouvée"; exit 1; }

P=/sys/module/battery/parameters/cache_time
old=$(<"$P")
trap 'echo "$old" >"$P"' EXIT
echo 0 >"$P"

TIMEFORMAT='%3R s'
for _ in 1 2 3 4 5; do
  time cat "$BAT"/voltage_now >/dev/null
done
