#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2119,SC2120
# Tests du correctif 8 (VBT corrigée pour la dalle AUO 0xE295).
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corr="$ici/.."
. "$ici/../../../tests/outils.sh"

FW=/usr/lib/firmware/updates/gs76/vbt-auo-e295.bin
MODPROBE=/etc/modprobe.d/gs76-vbt.conf
INITCPIO=/etc/mkinitcpio.conf.d/zz-gs76-vbt.conf

# fabrique_vbt <fichier> <psr hex> <drrs hex> [version BDB] : VBT minimale valide (blocs 40 et 44).
fabrique_vbt() {
    python3 -I - "$1" "$2" "$3" "${4:-243}" <<'PY'
import struct, sys
dst, psr, drrs, ver = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16), int(sys.argv[4])
b40 = bytes([255, 3]) + bytes(32)
b44 = bytes(24) + struct.pack('<HH', psr, drrs) + bytes(30)
blocs = b''.join(bytes([i]) + struct.pack('<H', len(b)) + b for i, b in ((40, b40), (44, b44)))
bdb = b'BIOS_DATA_BLOCK ' + struct.pack('<HHH', ver, 22, 22 + len(blocs)) + blocs
entete = bytearray(b'$VBT TIGERLAKE      ' + struct.pack('<HHHBB', 100, 48, 48 + len(bdb), 0, 0) + struct.pack('<I', 48) + bytes(16))
d = entete + bdb
d[26] = (-sum(d)) % 256
open(dst, 'wb').write(d + bytes(96))        # le noyau expose un tampon plus long que vbt_size
PY
}

# Générateur seul.
tmp="$(mktemp -d)"; _DOSSIERS_TEMP+=("$tmp")
fabrique_vbt "$tmp/origine.bin" bffc bffc
python3 -I "$corr/vbt-corriger.py" "$tmp/origine.bin" "$tmp/corrigee.bin" >/dev/null 2>&1; code=$?
verifie "générateur : code 0 sur une VBT valide" test "$code" -eq 0
verifie "générateur : deux octets changés (bit PSR et somme de contrôle)" test "$(cmp -l "$tmp/origine.bin" "$tmp/corrigee.bin" 2>/dev/null | wc -l)" -eq 2
verifie "générateur : PSR à 1, DRRS laissé à 0 pour l'entrée 0" python3 -I -c "import struct,sys; d=open('$tmp/corrigee.bin','rb').read(); i=d.index(bytes([44]),70); p,r=struct.unpack_from('<HH',d,i+3+24); sys.exit(0 if (p&1, r&1)==(1,0) else 1)"
verifie "générateur : somme de contrôle nulle" python3 -I -c "import sys; sys.exit(sum(open('$tmp/corrigee.bin','rb').read()) % 256)"
verifie "générateur : sortie tronquée à vbt_size" test "$(stat -c %s "$tmp/corrigee.bin")" -eq "$(( $(stat -c %s "$tmp/origine.bin") - 96 ))"
verifie "générateur : --verifier refuse la VBT d'origine" bash -c "! python3 -I '$corr/vbt-corriger.py' --verifier '$tmp/origine.bin' 2>/dev/null"
verifie "générateur : --verifier accepte la VBT corrigée" python3 -I "$corr/vbt-corriger.py" --verifier "$tmp/corrigee.bin"
python3 -I "$corr/vbt-corriger.py" "$tmp/corrigee.bin" "$tmp/deux.bin" >/dev/null 2>&1
verifie "générateur : idempotent" cmp -s "$tmp/corrigee.bin" "$tmp/deux.bin"
# VBT en service corrigée par l'ancienne version (PSR et DRRS à 1) : DRRS remis à 0, même résultat.
fabrique_vbt "$tmp/ancienne.bin" bffd bffd
verifie "générateur : --verifier refuse l'ancienne VBT (DRRS à 1)" bash -c "! python3 -I '$corr/vbt-corriger.py' --verifier '$tmp/ancienne.bin' 2>/dev/null"
python3 -I "$corr/vbt-corriger.py" "$tmp/ancienne.bin" "$tmp/depuis-ancienne.bin" >/dev/null 2>&1
verifie "générateur : depuis l'ancienne VBT, même résultat que depuis l'origine" cmp -s "$tmp/corrigee.bin" "$tmp/depuis-ancienne.bin"
fabrique_vbt "$tmp/vieille.bin" bffc bffc 227
verifie "générateur : refuse une BDB antérieure à 228" bash -c "! python3 -I '$corr/vbt-corriger.py' '$tmp/vieille.bin' '$tmp/x.bin' 2>/dev/null"
printf 'pas une vbt' >"$tmp/faux.bin"
verifie "générateur : refuse un fichier quelconque" bash -c "! python3 -I '$corr/vbt-corriger.py' '$tmp/faux.bin' '$tmp/x.bin' 2>/dev/null"
cp "$tmp/origine.bin" "$tmp/abimee.bin"; printf '\x01' | dd of="$tmp/abimee.bin" bs=1 seek=60 conv=notrunc 2>/dev/null
verifie "générateur : refuse une somme de contrôle fausse" bash -c "! python3 -I '$corr/vbt-corriger.py' '$tmp/abimee.bin' '$tmp/x.bin' 2>/dev/null"

# edid <fichier> <8 chiffres hex : fabricant + produit>
edid() { python3 -I -c "import sys; open(sys.argv[1],'wb').write(bytes.fromhex('00ffffffffffff00'+sys.argv[2])+bytes(116))" "$1" "$2"; }

preparer() {
    faux_systeme
    mkdir -p "$RACINE/sys/class/dmi/id" "$RACINE/sys/kernel/debug/dri/0000:00:02.0" "$RACINE/sys/class/drm/card1-eDP-1" "$RACINE/proc"
    echo "GS76 Stealth 11UH" >"$RACINE/sys/class/dmi/id/product_name"
    echo "E17M1IMS.119" >"$RACINE/sys/class/dmi/id/bios_version"
    echo i915 >"$RACINE/sys/kernel/debug/dri/0000:00:02.0/name"
    fabrique_vbt "$RACINE/sys/kernel/debug/dri/0000:00:02.0/i915_vbt" bffc bffc
    edid "$RACINE/sys/class/drm/card1-eDP-1/edid" 06af95e2
    echo "btime 2000000000" >"$RACINE/proc/stat"
    faux_cmd id 'echo 0'
    faux_cmd snapper 'echo "snapper $*" >>"$RACINE/journal"'
    faux_cmd limine-mkinitcpio 'echo "limine-mkinitcpio" >>"$RACINE/journal"; [ ! -e "$RACINE/initramfs-en-panne" ]'
    faux_cmd journalctl 'cat "$RACINE/journal-noyau" 2>/dev/null'
    echo "kernel: Setting dangerous option vbt_firmware - tainting kernel" >"$RACINE/journal-noyau"
}
installer() { bash "$corr/installer.sh" "$@" >"$RACINE/sortie" 2>&1; }
desinstaller() { bash "$corr/desinstaller.sh" >"$RACINE/sortie" 2>&1; }
verifier() { bash "$corr/verifier.sh" >"$RACINE/sortie" 2>&1; }

preparer
verifier; code=$?
verifie "avant installation : code 1" test "$code" -eq 1
verifie "avant installation : ABSENT" grep -q '^ABSENT ' "$RACINE/sortie"

installer; code=$?
verifie "installation : code 0" test "$code" -eq 0
verifie "installation : VBT corrigée posée" python3 -I "$corr/vbt-corriger.py" --verifier "$RACINE$FW"
verifie "installation : option i915 identique au dépôt" cmp -s "$corr/gs76-vbt.conf" "$RACINE$MODPROBE"
verifie "installation : fichier ajouté à l'initramfs" cmp -s "$corr/zz-gs76-vbt.conf" "$RACINE$INITCPIO"
verifie "installation : instantané demandé" grep -q '^snapper ' "$RACINE/journal"
verifie "installation : initramfs reconstruits" grep -q '^limine-mkinitcpio' "$RACINE/journal"
verifie "installation : redémarrage annoncé" grep -qi 'redémarr' "$RACINE/sortie"
verifier; code=$?
verifie "après installation et redémarrage : code 0" test "$code" -eq 0
verifie "après installation et redémarrage : OK" grep -q '^OK ' "$RACINE/sortie"

# Seconde installation, alors que la VBT en service est déjà la version corrigée.
cp "$RACINE$FW" "$RACINE/sys/kernel/debug/dri/0000:00:02.0/i915_vbt"
avant="$(sha256sum <"$RACINE$FW")"
installer; code=$?
verifie "seconde installation : code 0" test "$code" -eq 0
verifie "seconde installation : même VBT" test "$(sha256sum <"$RACINE$FW")" = "$avant"

# Pas encore redémarré : le journal du noyau ne mentionne pas l'option.
echo "kernel: i915 0000:00:02.0: [drm] Finished loading DMC firmware" >"$RACINE/journal-noyau"
echo "btime 1" >"$RACINE/proc/stat"
verifier; code=$?
verifie "installé, pas redémarré : code 2" test "$code" -eq 2
verifie "installé, pas redémarré : dit de redémarrer" grep -q 'redémarrer' "$RACINE/sortie"

# Journal du noyau illisible sans privilèges (vide) : pas de défaut, preuve limitée aux fichiers.
: >"$RACINE/journal-noyau"
verifier; code=$?
verifie "journal illisible : code 0" test "$code" -eq 0
verifie "journal illisible : le dit" grep -q 'fichiers seulement' "$RACINE/sortie"

# Le noyau n'a pas trouvé le fichier.
echo 'kernel: i915 0000:00:02.0: [drm] *ERROR* Requesting VBT firmware "gs76/vbt-auo-e295.bin" failed (-2)' >"$RACINE/journal-noyau"
verifier; code=$?
verifie "chargement en échec : code 2" test "$code" -eq 2
verifie "chargement en échec : DÉFAUT" grep -q '^DÉFAUT .*VBT' "$RACINE/sortie"

# DRRS « seamless » encore en service : l'ancienne VBT (PSR et DRRS) est chargée.
mkdir -p "$RACINE/sys/kernel/debug/dri/0000:00:02.0/eDP-1"
echo "DRRS type: seamless" >"$RACINE/sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_drrs_type"
echo "kernel: Setting dangerous option vbt_firmware - tainting kernel" >"$RACINE/journal-noyau"
verifier; code=$?
verifie "DRRS seamless en service : code 2" test "$code" -eq 2
verifie "DRRS seamless en service : dit de redémarrer" grep -q '^DÉFAUT .*DRRS.*redémarrer' "$RACINE/sortie"
echo "DRRS type: static" >"$RACINE/sys/kernel/debug/dri/0000:00:02.0/eDP-1/i915_drrs_type"
verifier; code=$?
verifie "DRRS non seamless : code 0" test "$code" -eq 0
verifie "DRRS non seamless : preuve citée" grep -q '^OK .*sans DRRS' "$RACINE/sortie"

# Fichiers altérés.
preparer; installer
echo "options i915 vbt_firmware=autre.bin" >"$RACINE$MODPROBE"
verifier; code=$?
verifie "option modifiée : code 2" test "$code" -eq 2
preparer; installer
fabrique_vbt "$RACINE$FW" bffd bffd
verifier; code=$?
verifie "VBT installée avec DRRS (ancienne version) : code 2" test "$code" -eq 2
fabrique_vbt "$RACINE$FW" bffc bffc
verifier; code=$?
verifie "VBT installée non corrigée : code 2" test "$code" -eq 2

# Désinstallation.
preparer; installer
: >"$RACINE/journal"
desinstaller; code=$?
verifie "désinstallation : code 0" test "$code" -eq 0
verifie "désinstallation : VBT retirée" test ! -e "$RACINE$FW"
verifie "désinstallation : option retirée" test ! -e "$RACINE$MODPROBE"
verifie "désinstallation : ajout à l'initramfs retiré" test ! -e "$RACINE$INITCPIO"
verifie "désinstallation : dossier firmware vide retiré" test ! -d "$RACINE/usr/lib/firmware/updates/gs76"
verifie "désinstallation : initramfs reconstruits" grep -q '^limine-mkinitcpio' "$RACINE/journal"
verifier; code=$?
verifie "après désinstallation : code 1" test "$code" -eq 1

# Un second connecteur eDP sans écran (EDID vide, comme sur la carte NVIDIA) ne doit pas gêner.
preparer
mkdir -p "$RACINE/sys/class/drm/card0-eDP-2"
: >"$RACINE/sys/class/drm/card0-eDP-2/edid"
installer; code=$?
verifie "connecteur eDP vide avant le bon : installation réussie" test "$code" -eq 0
verifie "connecteur eDP vide avant le bon : pas de sortie muette" grep -q '^OK ' "$RACINE/sortie"

# Refus avant tout changement.
preparer
edid "$RACINE/sys/class/drm/card1-eDP-1/edid" 06af95de
installer; code=$?
verifie "autre dalle : refus" test "$code" -ne 0
verifie "autre dalle : rien installé" test ! -e "$RACINE$FW" -a ! -e "$RACINE$MODPROBE"
installer --force; code=$?
verifie "autre dalle avec --force : installé" test "$code" -eq 0

preparer
rm "$RACINE/sys/kernel/debug/dri/0000:00:02.0/i915_vbt"
installer; code=$?
verifie "VBT illisible : refus" test "$code" -ne 0
verifie "VBT illisible : rien installé" test ! -e "$RACINE$MODPROBE"

preparer
printf 'pas une vbt' >"$RACINE/sys/kernel/debug/dri/0000:00:02.0/i915_vbt"
installer; code=$?
verifie "VBT invalide : refus" test "$code" -ne 0
verifie "VBT invalide : rien installé" test ! -e "$RACINE$FW" -a ! -e "$RACINE$MODPROBE"

preparer
touch "$RACINE/initramfs-en-panne"
installer; code=$?
verifie "reconstruction en échec : code non nul" test "$code" -ne 0
verifie "reconstruction en échec : message explicite" grep -q '^ÉCHEC .*initramfs' "$RACINE/sortie"

preparer
echo Autre >"$RACINE/sys/class/dmi/id/product_name"
installer; code=$?
verifie "matériel inconnu : refus" test "$code" -ne 0
verifie "matériel inconnu : rien installé" test ! -e "$RACINE$MODPROBE"

fin
