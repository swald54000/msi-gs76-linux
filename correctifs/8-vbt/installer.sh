#!/usr/bin/env bash
# shellcheck disable=SC1091
# Installe une VBT corrigée pour la dalle AUO 0xE295 : PSR reconnu par i915, DRRS laissé éteint.
# La VBT est générée à partir de celle de la machine ; prend effet au prochain démarrage.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
FW=/usr/lib/firmware/updates/gs76/vbt-auo-e295.bin
MODPROBE=/etc/modprobe.d/gs76-vbt.conf
INITCPIO=/etc/mkinitcpio.conf.d/zz-gs76-vbt.conf
DALLE=06af95e2   # identifiant EDID : fabricant AUO, produit 0xE295

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done

exiger_root
verifier_materiel "${forcer[@]}" || exit 1

# Vérifications préalables, avant tout changement.
if ! command -v python3 >/dev/null 2>&1; then
    echec "python3 est introuvable : il sert à générer la VBT corrigée. Rien n'a été modifié."
    exit 1
fi

source_vbt=""
for d in "$RACINE"/sys/kernel/debug/dri/*; do
    if grep -qs i915 "$d/name" && [ -r "$d/i915_vbt" ]; then
        source_vbt="$d/i915_vbt"
        break
    fi
done
if [ -z "$source_vbt" ]; then
    echec "VBT de la machine illisible (sys/kernel/debug/dri/*/i915_vbt) : debugfs monté et pilote i915 chargé ? Rien n'a été modifié."
    exit 1
fi

dalle=""
for e in "$RACINE"/sys/class/drm/card*-eDP-*/edid; do
    # Pas de test de taille : les fichiers de sysfs annoncent 0 octet.
    [ -r "$e" ] || continue
    # « || true » : od échoue sur l'EDID vide d'un connecteur sans écran (carte NVIDIA).
    dalle="$(od -An -tx1 -j8 -N4 "$e" 2>/dev/null | tr -d ' \n' || true)"
    [ -n "$dalle" ] && break
done
if [ "$dalle" != "$DALLE" ]; then
    if [ "${#forcer[@]}" -eq 0 ]; then
        echec "dalle interne « ${dalle:-inconnue} » : ce correctif vise la dalle AUO 0xE295 ($DALLE), absente de la VBT de MSI. Utilisez --force pour passer outre. Rien n'a été modifié."
        exit 1
    fi
    avertir "dalle interne « ${dalle:-inconnue} » (attendu $DALLE) : poursuite forcée."
fi

temp="$(mktemp)"
trap 'rm -f "$temp"' EXIT
if ! python3 -I "$ici/vbt-corriger.py" "$source_vbt" "$temp"; then
    echec "la VBT de la machine n'a pas pu être corrigée. Rien n'a été modifié."
    exit 1
fi

info "instantané avant installation (démarrable depuis le menu Limine en cas de problème)"
instantane "avant VBT corrigée GS76"

sauvegarder "$FW"
sauvegarder "$MODPROBE"
sauvegarder "$INITCPIO"

info "installation de la VBT corrigée"
mkdir -p "$RACINE$(dirname "$FW")" "$RACINE$(dirname "$MODPROBE")" "$RACINE$(dirname "$INITCPIO")"
install -m644 "$temp" "$RACINE$FW"
install -m644 "$ici/gs76-vbt.conf" "$RACINE$MODPROBE"
install -m644 "$ici/zz-gs76-vbt.conf" "$RACINE$INITCPIO"

info "reconstruction des initramfs"
if ! reconstruire_initramfs; then
    echec "la reconstruction de l'initramfs a échoué : la VBT corrigée ne sera pas chargée tant qu'une reconstruction n'aura pas réussi (ou que desinstaller.sh n'aura pas été lancé)."
    exit 1
fi

ok "VBT corrigée installée : redémarrer pour qu'elle soit chargée."
info "si l'écran interne pose problème au démarrage : entrée « Snapshots » du menu Limine, puis desinstaller.sh."
