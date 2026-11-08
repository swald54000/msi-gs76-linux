#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (hypothèse non confirmée, voir ../README.fr.md), à lancer avec sudo.
# Installe le fragment de ligne de commande noyau pour limine-entry-tool, puis
# régénère limine.conf. Effet au prochain démarrage. Annuler : uninstall.sh.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
install -m 644 "$ici/msi-gs76-usb.conf" /etc/limine-entry-tool.d/msi-gs76-usb.conf
limine-update
echo "--- Vérification :"
grep -c 'usbcore.quirks=1038:113a:k' /boot/limine.conf | sed 's/^/entrées limine avec le quirk : /'
