#!/usr/bin/env bash
# SC2015 : ok() réussit toujours, « A && ok || echec » est donc sûr.
# shellcheck disable=SC1091,SC2015
# Outil de recherche : compare ce qu'expose msi-ec (branche gs76) à un dump de
# l'EC lu en LECTURE SEULE.
#
#   sudo verifier-sysfs.sh                 dump en direct via ec_sys write_support=0
#   verifier-sysfs.sh DUMP.bin             compare à un dump existant
#   sudo verifier-sysfs.sh --surveiller N  un dump toutes les 10 s pendant N s (GPU, auxiliaire)
#
# Variables : SEUIL_CHARGE (limite de charge attendue, défaut 80) ; RACINE ou
# VERIF_SYSFS_ROOT (préfixe du système de fichiers, pour les tests).
# Code de sortie = nombre d'échecs.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
RACINE=${RACINE:-${VERIF_SYSFS_ROOT:-}}
ROOT=$RACINE
SEUIL_CHARGE=${SEUIL_CHARGE:-80}
EC=$ROOT/sys/devices/platform/msi-ec
dossier_batterie="$(batterie || true)"
BAT=${dossier_batterie:-$ROOT/sys/class/power_supply/batterie-introuvable}/charge_control_end_threshold
echecs=0
ok()    { echo "OK $*"; }
echec() { echo "ÉCHEC $*"; echecs=$((echecs + 1)); }

detecte_msi_ec_absent()  { [ ! -d "$EC" ]; }
detecte_pilote_origine() { [ -d "$EC" ] && [ ! -e "$EC/cpu/fan_curve" ]; }

hwmon_msi_ec() {
	local n
	for n in "$ROOT"/sys/class/hwmon/hwmon*/name; do
		[ "$(cat "$n" 2>/dev/null)" = msi_ec ] && { dirname "$n"; return 0; }
	done
	return 1
}

# Octet i (décimal) du dump.
octet() { od -An -tu1 -j "$2" -N1 "$1" | tr -d ' '; }
octets() { local f=$1 a=$2 n=$3 i out=(); for ((i = 0; i < n; i++)); do out+=("$(octet "$f" $((a + i)))"); done; echo "${out[*]}"; }
rpm_dump() {
	local p
	p=$(( $(octet "$1" "$2") * 256 + $(octet "$1" $(($2 + 1))) ))
	[ "$p" -eq 0 ] && echo 0 || echo $((480000 / p))
}
courbe_dump() { # s0 t1 s1 … t6 s6
	local f=$1 t=$2 s=$3 i seq
	seq=("$(octet "$f" "$s")")
	for ((i = 0; i < 6; i++)); do seq+=("$(octet "$f" $((t + i)))" "$(octet "$f" $((s + i + 1)))"); done
	echo "${seq[*]}"
}

dump_direct() { # $1 = fichier de sortie ; ec_sys en lecture seule uniquement
	[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo (ou donner un dump)"; exit 99; }
	modprobe ec_sys write_support=0 || exit 99
	[ "$(cat /sys/module/ec_sys/parameters/write_support)" = N ] || { echo "ec_sys est en écriture, abandon"; exit 99; }
	mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
	cp /sys/kernel/debug/ec/ec0/io "$1"
}
fin_direct() { modprobe -r ec_sys 2>/dev/null || true; }

compare_exact() { # libellé, attendu, fichier sysfs
	local lu
	lu=$(cat "$3" 2>/dev/null) || { echec "$1 : $3 illisible"; return; }
	[ "$lu" = "$2" ] && ok "$1 ($lu)" || echec "$1 : sysfs « $lu », EC « $2 »"
}
compare_rpm() { # libellé, attendu, fichier ; ±10 %, 0 ↔ 0
	local lu
	lu=$(cat "$3" 2>/dev/null) || { echec "$1 : $3 illisible"; return; }
	if [ "$2" -eq 0 ] || [ "$lu" -eq 0 ]; then
		[ "$lu" -eq "$2" ] && ok "$1 ($lu tr/min)" || echec "$1 : sysfs $lu, EC $2 tr/min"
	elif [ $(( (lu - $2) * 100 / $2 )) -le 10 ] && [ $(( ($2 - lu) * 100 / $2 )) -le 10 ]; then
		ok "$1 ($lu tr/min, EC $2)"
	else
		echec "$1 : sysfs $lu, EC $2 tr/min"
	fi
}

verifie() { # $1 = dump
	local d=$1 h lu
	if detecte_msi_ec_absent; then echec "msi-ec absent (limite de charge non appliquée)"; return; fi
	if detecte_pilote_origine; then echec "pilote d'origine chargé (pas de fan_curve)"; return; fi
	compare_exact "courbe CPU" "$(courbe_dump "$d" 0x6A 0x72)" "$EC/cpu/fan_curve"
	compare_exact "courbe GPU" "$(courbe_dump "$d" 0x82 0x8A)" "$EC/gpu/fan_curve"
	compare_exact "hystérésis CPU" "$(octets "$d" 0x7A 6)" "$EC/cpu/fan_curve_hysteresis"
	compare_exact "hystérésis GPU" "$(octets "$d" 0x92 6)" "$EC/gpu/fan_curve_hysteresis"
	case $(octet "$d" 0xBF) in 40) lu=on ;; 8) lu=off ;; *) lu="inconnu" ;; esac
	compare_exact "partage USB" "$lu" "$EC/usb_share"
	lu=$(cat "$EC/cpu/realtime_temperature" 2>/dev/null || echo -999)
	[ $((lu - $(octet "$d" 0x68))) -le 2 ] && [ $(($(octet "$d" 0x68) - lu)) -le 2 ] \
		&& ok "température CPU ($lu °C)" || echec "température CPU : sysfs $lu, EC $(octet "$d" 0x68)"
	if h=$(hwmon_msi_ec); then
		compare_rpm "ventilateur CPU" "$(rpm_dump "$d" 0xC8)" "$h/fan1_input"
		compare_rpm "ventilateur GPU" "$(rpm_dump "$d" 0xCA)" "$h/fan2_input"
		[ -e "$h/fan3_input" ] && compare_rpm "ventilateur auxiliaire" "$(rpm_dump "$d" 0xCC)" "$h/fan3_input"
	else
		echec "hwmon msi_ec absent"
	fi
	lu=$(cat "$BAT" 2>/dev/null || echo "?")
	[ "$lu" = "$SEUIL_CHARGE" ] && ok "limite de charge ($SEUIL_CHARGE %)" || echec "limite de charge : $lu au lieu de $SEUIL_CHARGE"
}

if [ "${1:-}" = "--surveiller" ]; then
	duree=${2:?durée en secondes}
	tmpd=$(mktemp -d); trap 'fin_direct; rm -rf "$tmpd"' EXIT
	h=$(hwmon_msi_ec) || { echo "hwmon msi_ec absent"; exit 1; }
	for ((t = 0; t <= duree; t += 10)); do
		dump_direct "$tmpd/io"
		echo "t=${t}s GPU $(octet "$tmpd/io" 0x80) °C | EC GPU $(rpm_dump "$tmpd/io" 0xCA) aux $(rpm_dump "$tmpd/io" 0xCC) tr/min | hwmon GPU $(cat "$h/fan2_input") aux $(cat "$h/fan3_input" 2>/dev/null || echo -)"
		fin_direct
		[ "$t" -lt "$duree" ] && sleep 10
	done
	exit 0
fi

if [ $# -ge 1 ]; then
	verifie "$1"
else
	tmpd=$(mktemp -d); trap 'fin_direct; rm -rf "$tmpd"' EXIT
	dump_direct "$tmpd/io"
	verifie "$tmpd/io"
fi
echo "$echecs échec(s)"
exit "$echecs"
