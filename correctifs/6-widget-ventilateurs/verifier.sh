#!/usr/bin/env bash
# Vérifie le widget ventilateurs (plugin Omarchy). Sans privilèges.
# Sortie : OK|ABSENT|DÉFAUT <détail> ; code 0 sain, 1 absent, 2 défaut.
set -u
RACINE="${RACINE:-}"
plugin="${HOME}/.config/omarchy/plugins/swald.fans/manifest.json"
fan_mode="$RACINE/sys/devices/platform/msi-ec/fan_mode"

if [ ! -f "$plugin" ]; then
    echo "ABSENT widget ventilateurs non installé (plugin swald.fans)"
    exit 1
fi
if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx 'msi-ec'; then
    echo "DÉFAUT l'utilisateur n'est pas dans le groupe msi-ec : installer le correctif 1, puis vous reconnecter (fermer et rouvrir la session)"
    exit 2
fi
if [ ! -e "$fan_mode" ]; then
    echo "DÉFAUT pilote msi-ec absent (fan_mode introuvable) : installer le correctif 1"
    exit 2
fi
read -r groupe droits < <(stat -c '%G %A' "$fan_mode" 2>/dev/null || true)
if [ "${groupe:-}" != "msi-ec" ]; then
    echo "DÉFAUT groupe de fan_mode : « ${groupe:-inconnu} » au lieu de msi-ec (règle udev non appliquée)"
    exit 2
fi
if [ "${droits:0:6}" != "${droits:0:5}w" ]; then
    echo "DÉFAUT fan_mode non inscriptible par le groupe msi-ec (droits ${droits:-inconnus})"
    exit 2
fi
echo "OK widget installé, utilisateur dans le groupe msi-ec, fan_mode inscriptible"
exit 0
