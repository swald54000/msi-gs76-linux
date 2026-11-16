#!/usr/bin/env bash
# shellcheck disable=SC1091
# Vérifie la VBT corrigée. Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
fw="$RACINE/usr/lib/firmware/updates/gs76/vbt-auo-e295.bin"
modprobe="$RACINE/etc/modprobe.d/gs76-vbt.conf"
initcpio="$RACINE/etc/mkinitcpio.conf.d/zz-gs76-vbt.conf"

if [ ! -f "$fw" ] && [ ! -f "$modprobe" ]; then
    echo "ABSENT VBT corrigée non installée"
    exit 1
fi
if [ ! -f "$fw" ] || [ ! -f "$modprobe" ] || [ ! -f "$initcpio" ]; then
    echo "DÉFAUT installation incomplète (VBT, option i915 ou ajout à l'initramfs manquant) : relancer l'installateur"
    exit 2
fi
if ! cmp -s "$ici/gs76-vbt.conf" "$modprobe" || ! cmp -s "$ici/zz-gs76-vbt.conf" "$initcpio"; then
    echo "DÉFAUT option i915 ou ajout à l'initramfs différent de la version du dépôt : relancer l'installateur"
    exit 2
fi
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -I "$ici/vbt-corriger.py" --verifier "$fw" 2>/dev/null; then
        echo "DÉFAUT VBT installée invalide ou non corrigée : relancer l'installateur"
        exit 2
    fi
else
    info "python3 absent : contenu de la VBT installée non vérifié"
fi

# Précise si l'installation est postérieure au dernier démarrage (redémarrage nécessaire).
btime="$(sed -n 's/^btime \([0-9][0-9]*\)$/\1/p' "$RACINE/proc/stat" 2>/dev/null | head -n 1)"
mtime="$(stat -c %Y "$fw" 2>/dev/null || true)"
if [ -n "$btime" ] && [ -n "$mtime" ] && [ "$mtime" -gt "$btime" ]; then
    cause="installée après le dernier démarrage : redémarrer"
else
    cause="option absente malgré un démarrage postérieur à l'installation"
fi

# Journal du noyau du démarrage en cours.
if journal="$(journalctl -k -b 2>/dev/null)" && [ -n "$journal" ]; then
    if grep -q 'Requesting VBT firmware.*failed' <<<"$journal"; then
        echo "DÉFAUT le noyau n'a pas trouvé la VBT corrigée (« Requesting VBT firmware … failed ») : il utilise la VBT du BIOS ; reconstruire l'initramfs"
        exit 2
    fi
    if ! grep -q 'vbt_firmware' <<<"$journal"; then
        echo "DÉFAUT VBT corrigée installée mais non prise en compte par le noyau : $cause"
        exit 2
    fi
    preuve="journal du noyau"
else
    info "journal du noyau illisible sans privilèges : chargement non vérifié"
    preuve="fichiers seulement"
fi

# Type de DRRS retenu par i915 : lisible seulement pour root.
for t in "$RACINE"/sys/kernel/debug/dri/*/eDP-*/i915_drrs_type; do
    [ -r "$t" ] || continue
    if ! grep -q seamless "$t"; then
        echo "DÉFAUT VBT chargée mais DRRS « $(sed 's/.*: //' "$t") » au lieu de « seamless »"
        exit 2
    fi
    preuve="$preuve, DRRS seamless"
done

echo "OK VBT corrigée chargée (preuves : $preuve) : PSR et DRRS reconnus pour la dalle"
exit 0
