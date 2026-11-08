#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root), version de travail de ce qu'installe correctifs/5-ecran.
# Autorise le PSR1 sur la dalle interne à chaque démarrage (la VBT de MSI le désactive,
# et sur ce noyau i915.enable_psr=1 ne passe pas outre : i915 journalise toujours
# « PSR disabled by flag »). Le réglage debugfs d'i915 FORCE_PSR1 (0x3) le fait ;
# i915 vérifie quand même la temporisation de la dalle pour chaque mode, donc le PSR
# reste coupé à 360 Hz (temps d'établissement de 330 µs trop long) et s'active à 60 Hz.
# Annuler : systemctl disable --now i915-psr-force.service && rm /etc/systemd/system/i915-psr-force.service
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root

# Retire le paramètre noyau inefficace ajouté auparavant
if [[ -f /etc/limine-entry-tool.d/i915-psr.conf ]]; then
  rm /etc/limine-entry-tool.d/i915-psr.conf
  limine-mkinitcpio
fi

cat >/etc/systemd/system/i915-psr-force.service <<'EOF'
[Unit]
Description=Allow PSR1 on the internal panel (MSI VBT disables it)
After=sys-kernel-debug.mount systemd-modules-load.service
Requires=sys-kernel-debug.mount

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for d in /sys/kernel/debug/dri/*; do grep -qs i915 "$d/name" && [ -w "$d/i915_edp_psr_debug" ] && echo 0x3 >"$d/i915_edp_psr_debug" && exit 0; done; exit 1'
ExecStop=/bin/sh -c 'for d in /sys/kernel/debug/dri/*; do grep -qs i915 "$d/name" && [ -w "$d/i915_edp_psr_debug" ] && echo 0x0 >"$d/i915_edp_psr_debug"; done; true'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now i915-psr-force.service
sleep 2
echo
echo "Service : $(systemctl is-active i915-psr-force.service)"
grep -h 'PSR mode' /sys/kernel/debug/dri/*/i915_edp_psr_status | sort -u
