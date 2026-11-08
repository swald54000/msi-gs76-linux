#!/usr/bin/env bash
# shellcheck disable=SC1091
# Charge au démarrage une SSDT en ajout seul (MSI GS76 11UH) :
#  - \_TZ.ETMD est défini, donc \_SB.IETM._OSC (Intel DTT) n'échoue plus ;
#  - PS2M.I2CT = 1 : le pavé tactile I2C-HID n'est plus aussi détecté comme souris PS/2.
# Retour arrière : desinstaller.sh, ou l'instantané Limine/Snapper pris avant l'installation.
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"

RACINE="${RACINE:-}"
AML=/etc/initcpio/acpi_override/ssdt-gs76.aml
CONF=/etc/mkinitcpio.conf.d/zz-acpi-override.conf

forcer=()
for arg in "$@"; do
    case "$arg" in
        --force) forcer=(--force) ;;
        *) echec "option inconnue : $arg"; exit 1 ;;
    esac
done

exiger_root
verifier_materiel "${forcer[@]}" || exit 1

if [ -e "$RACINE/etc/initcpio/acpi_override/dsdt.aml" ]; then
    echec "l'ancienne DSDT complète (dsdt.aml) est encore installée : retirez-la d'abord."
    exit 1
fi

if [ ! -e "$RACINE/usr/lib/initcpio/install/acpi_override" ] && [ ! -e "$RACINE/etc/initcpio/install/acpi_override" ]; then
    echec "le hook mkinitcpio « acpi_override » est introuvable (usr/lib/initcpio/install ou etc/initcpio/install) : sans lui la table ne serait jamais chargée. Rien n'a été modifié."
    exit 1
fi

info "instantané avant installation (démarrable depuis le menu Limine en cas de problème)"
instantane "avant SSDT GS76 (acpi_override)"

sauvegarder "$AML"
sauvegarder "$CONF"

info "installation de la table"
mkdir -p "$RACINE$(dirname "$AML")" "$RACINE$(dirname "$CONF")"
install -m644 "$ici/ssdt-gs76.aml" "$RACINE$AML"
echo 'HOOKS+=(acpi_override)' >"$RACINE$CONF"

info "reconstruction des initramfs"
if ! reconstruire_initramfs; then
    echec "la reconstruction de l'initramfs a échoué : l'initramfs n'a pas été reconstruit et la table ne sera pas chargée tant qu'une reconstruction n'aura pas réussi (ou que desinstaller.sh n'aura pas été lancé)."
    exit 1
fi

ok "SSDT installée."
info "vérification (à titre indicatif, sans effet sur le résultat de l'installation ; avant le redémarrage elle signale normalement que la table n'est pas encore chargée) :"
bash "$ici/verifier.sh" || true
info "un redémarrage est nécessaire pour que la table soit chargée ; relancez ensuite verifier.sh."
