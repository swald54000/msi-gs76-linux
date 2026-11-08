#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2034
# Les désinstallateurs 2 à 5 ne doivent pas s'arrêter quand RACINE est vide
# (cas réel : l'expansion obligatoire sur RACINE faisait échouer le script sous set -e).
# Partie A : RACINE pointe vers un dossier temporaire, sans aucune sauvegarde.
# Partie B : RACINE vide, mais rm, rmdir, mkdir, cp, systemctl, mkinitcpio,
# limine-mkinitcpio et id sont de faux exécutables qui ne font que journaliser :
# les chemins réels n'apparaissent que comme arguments de ces faux outils.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
depot="$ici/.."
. "$ici/outils.sh"

# --- Partie A : RACINE temporaire, aucune sauvegarde -------------------------
fichiers_a() { # $1 = correctif ; fichiers que le désinstallateur doit retirer
    case "$1" in
        2-ssdt) echo /etc/initcpio/acpi_override/ssdt-gs76.aml /etc/mkinitcpio.conf.d/zz-acpi-override.conf ;;
        3-thermald) echo /etc/systemd/system/thermald.service.d/wait-rapl.conf ;;
        4-batterie) echo /usr/local/bin/battery-refresh /etc/systemd/system/battery-refresh.service \
            /etc/systemd/system/battery-refresh.timer /etc/tmpfiles.d/battery-cache.conf /etc/msi-gs76-linux/batterie.conf ;;
        5-ecran) echo /etc/systemd/system/i915-psr-force.service /usr/local/bin/edp-refresh-auto \
            /etc/systemd/user/edp-refresh-auto.service \
            /etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service ;;
    esac
}

for c in 2-ssdt 3-thermald 4-batterie 5-ecran; do
    faux_systeme
    for c2 in id systemctl mkinitcpio limine-mkinitcpio; do
        faux_cmd "$c2" '[ "${0##*/}" = id ] && echo 0; exit 0'
    done
    for f in $(fichiers_a "$c"); do
        mkdir -p "$RACINE$(dirname "$f")"
        : >"$RACINE$f"
    done
    bash "$depot/correctifs/$c/desinstaller.sh" >"$RACINE/sortie" 2>&1
    code=$?
    verifie "A $c : code 0 sans sauvegarde" test "$code" -eq 0
    restes=0
    for f in $(fichiers_a "$c"); do [ -e "$RACINE$f" ] && restes=$((restes + 1)); done
    verifie "A $c : fichiers retirés" test "$restes" -eq 0
done

# --- Partie B : RACINE vide, tous les outils d'écriture sont des faux ---------
if [ "$(/usr/bin/id -u)" -eq 0 ]; then
    echo "skip partie B : lancée en root, refus par prudence"
    fin
fi

attendu_b() { # chemins que le désinstallateur peut passer à rm / rmdir
    fichiers_a "$1"
    case "$1" in
        2-ssdt) echo /etc/initcpio/acpi_override ;;
        3-thermald) echo /etc/systemd/system/thermald.service.d ;;
        4-batterie) echo /etc/msi-gs76-linux /var/lib/msi-gs76-linux/batterie-cache_time.origine ;;
        5-ecran) echo /etc/systemd/user/graphical-session.target.wants ;;
    esac
}

for c in 2-ssdt 3-thermald 4-batterie 5-ecran; do
    faux_systeme
    PATH="$_PATH_ORIGINE" # PATH de l'environnement : le faux PATH n'est donné qu'au script testé
    journal="$RACINE/journal-faux"
    : >"$journal"
    for outil in rm rmdir mkdir cp systemctl mkinitcpio limine-mkinitcpio; do
        faux_cmd "$outil" 'printf "%s %s\n" "${0##*/}" "$*" >>"$JOURNAL_FAUX"; exit 0'
    done
    faux_cmd id 'echo 0'

    # Garde-fou : les faux outils doivent être résolus en premier, sinon on s'arrête.
    sur=1
    for outil in rm rmdir mkdir cp systemctl mkinitcpio limine-mkinitcpio id; do
        resolu="$(env -u RACINE PATH="$FAUX_BIN:$_PATH_ORIGINE" bash -c "command -v $outil")"
        [ "$resolu" = "$FAUX_BIN/$outil" ] || sur=0
    done
    verifie "B $c : les faux outils passent avant les vrais" test "$sur" -eq 1
    [ "$sur" -eq 1 ] || continue

    env RACINE= PATH="$FAUX_BIN:$_PATH_ORIGINE" JOURNAL_FAUX="$journal" \
        bash "$depot/correctifs/$c/desinstaller.sh" >"$RACINE/sortie" 2>&1
    code=$?
    verifie "B $c : code 0 avec RACINE vide" test "$code" -eq 0

    # Tout argument absolu de rm / rmdir doit faire partie des chemins attendus.
    inattendus=0
    while read -r outil option chemin; do
        case "$outil" in rm | rmdir) ;; *) continue ;; esac
        grep -qxF -- "$chemin" < <(attendu_b "$c" | tr " " "\n") || inattendus=$((inattendus + 1))
    done < <(grep -E '^(rm|rmdir) ' "$journal")
    verifie "B $c : rm / rmdir ne visent que les chemins attendus" test "$inattendus" -eq 0

    # Suppressions inconditionnelles (indépendantes des sauvegardes de la machine).
    case "$c" in
        4-batterie) fixe=/var/lib/msi-gs76-linux/batterie-cache_time.origine ;;
        5-ecran) fixe=/etc/systemd/user/graphical-session.target.wants/edp-refresh-auto.service ;;
        *) fixe="" ;;
    esac
    if [ -n "$fixe" ]; then
        verifie "B $c : rm -f $fixe" grep -qxF "rm -f $fixe" "$journal"
    fi

    # Les autres suppressions ne sont certaines que si la machine n'a ni sauvegardes ni autres tables.
    if [ ! -e /var/lib/msi-gs76-linux ] && ! compgen -G '/etc/initcpio/acpi_override/*.aml' >/dev/null; then
        manque=0
        for f in $(fichiers_a "$c"); do
            grep -qxF "rm -f $f" "$journal" || manque=$((manque + 1))
        done
        verifie "B $c : rm -f reçoit les chemins absolus attendus" test "$manque" -eq 0
    fi
done
fin
