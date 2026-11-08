#!/usr/bin/env bash
# Fonctions communes aux installateurs et vérificateurs.
# À sourcer : aucune sortie au chargement. Tous les accès au système de
# fichiers passent par le préfixe $RACINE (vide par défaut) pour les tests.
# shellcheck shell=bash

# --- Messages ---------------------------------------------------------------
ok() { printf 'OK %s\n' "$*"; }
info() { printf 'INFO %s\n' "$*"; }
avertir() { printf 'ATTENTION %s\n' "$*" >&2; }
# Signale une erreur sans arrêter le script.
echec() { printf 'ÉCHEC %s\n' "$*" >&2; }

# --- Privilèges -------------------------------------------------------------
exiger_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echec "ce script doit être lancé en root (sudo)."
        exit 1
    fi
}

# --- Matériel ---------------------------------------------------------------
# Retour 0 pour un GS76 avec firmware 17M1 ; --force contourne la vérification.
verifier_materiel() {
    local force=0 modele firmware source_fw
    [ "${1:-}" = "--force" ] && force=1

    modele="$(cat "${RACINE:-}/sys/class/dmi/id/product_name" 2>/dev/null || true)"
    if [ -r "${RACINE:-}/sys/devices/platform/msi-ec/fw_version" ]; then
        firmware="$(cat "${RACINE:-}/sys/devices/platform/msi-ec/fw_version" 2>/dev/null || true)"
        source_fw="fw_version msi-ec"
    else
        firmware="$(cat "${RACINE:-}/sys/class/dmi/id/bios_version" 2>/dev/null || true)"
        source_fw="BIOS"
    fi

    local modele_ok=0 firmware_ok=0
    case "$modele" in *GS76*) modele_ok=1 ;; esac
    if [ "$source_fw" = "BIOS" ]; then
        case "$firmware" in E17M1*) firmware_ok=1 ;; esac
    else
        case "$firmware" in 17M1*) firmware_ok=1 ;; esac
    fi

    if [ "$modele_ok" -eq 1 ] && [ "$firmware_ok" -eq 1 ]; then
        return 0
    fi
    if [ "$force" -eq 1 ]; then
        avertir "matériel non reconnu (modèle « ${modele:-inconnu} », ${source_fw} « ${firmware:-inconnu} ») : poursuite forcée."
        return 0
    fi
    echec "matériel non pris en charge : modèle « ${modele:-inconnu} », ${source_fw} « ${firmware:-inconnu} ». Attendu : GS76 avec firmware 17M1. Utilisez --force pour passer outre."
    return 1
}

# Affiche l'utilisateur qui a lancé sudo ; refuse vide ou root.
utilisateur_cible() {
    if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
        echec "utilisateur cible introuvable : lancez le script avec sudo depuis votre compte (pas en root direct)."
        return 1
    fi
    printf '%s\n' "$SUDO_USER"
}

# Affiche le chemin de la première vraie batterie (pas un périphérique).
batterie() {
    local d type scope
    for d in "${RACINE:-}"/sys/class/power_supply/*; do
        [ -d "$d" ] || continue
        type="$(cat "$d/type" 2>/dev/null || true)"
        scope="$(cat "$d/scope" 2>/dev/null || true)"
        if [ "$type" = "Battery" ] && [ "$scope" != "Device" ]; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    return 1
}

# --- Système ----------------------------------------------------------------
reconstruire_initramfs() {
    if command -v limine-mkinitcpio >/dev/null 2>&1; then
        limine-mkinitcpio
    else
        mkinitcpio -P
    fi
}

# Instantané snapper si disponible ; ne bloque jamais.
instantane() {
    if command -v snapper >/dev/null 2>&1; then
        snapper -c root create -d "$1" || avertir "instantané snapper impossible, on continue."
    else
        info "snapper absent : pas d'instantané (« $1 »)."
    fi
    return 0
}

# --- Sauvegardes ------------------------------------------------------------
_dossier_sauvegardes() { printf '%s\n' "${RACINE:-}/var/lib/msi-gs76-linux/sauvegardes"; }

# Sauvegarde le fichier d'origine, une seule fois (jamais écrasée).
sauvegarder() {
    local fichier="$1" dest
    dest="$(_dossier_sauvegardes)$fichier"
    [ -e "$dest" ] && return 0
    [ -e "${RACINE:-}$fichier" ] || return 0
    mkdir -p "$(dirname "$dest")"
    cp -p "${RACINE:-}$fichier" "$dest"
}

# Remet la sauvegarde, ou supprime le fichier s'il n'en existait pas.
restaurer() {
    local fichier="$1" src
    src="$(_dossier_sauvegardes)$fichier"
    if [ -e "$src" ]; then
        mkdir -p "$(dirname "${RACINE:-}$fichier")"
        cp -p "$src" "${RACINE:-}$fichier"
    else
        rm -f "${RACINE:-}$fichier"
    fi
}
