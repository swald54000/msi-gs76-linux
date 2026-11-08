#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche, à lancer avec sudo : retire le fragment installé par install.sh
# et régénère limine.conf.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
rm -f /etc/limine-entry-tool.d/msi-gs76-usb.conf
limine-update
