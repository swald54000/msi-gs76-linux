#!/usr/bin/env bash
# Fournit regle_udev : à sourcer.
# shellcheck shell=bash

# regle_udev <groupe> <seuil> <nom_batterie>
# Affiche la règle udev (une ligne) qui, à chaque liaison du pilote msi-ec,
# donne l'accès en écriture au groupe et fixe le seuil de charge.
regle_udev() {
    local groupe="$1" seuil="$2" batterie="$3"
    printf '%s\n' "ACTION==\"bind\", SUBSYSTEM==\"platform\", DRIVER==\"msi-ec\", RUN+=\"/usr/bin/sh -c 'cd /sys/devices/platform/msi-ec && chgrp ${groupe} shift_mode fan_mode cooler_boost && chmod g+w shift_mode fan_mode cooler_boost; echo ${seuil} > /sys/class/power_supply/${batterie}/charge_control_end_threshold'\""
}
