#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Recensement des réveils au vrai repos : qui réveille le
# CPU, et jusqu'où le package descend. Lecture seule.
# Attend 20 s (s'éloigner, ne rien toucher), puis enregistre 30 s.
# Écrit ./diag-wakeups.txt (dossier courant).
set -uo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root

OUT="$PWD/diag-wakeups.txt"
proprio="$(utilisateur_cible 2>/dev/null || true)"
DBG=/sys/kernel/debug
mountpoint -q $DBG || mount -t debugfs none $DBG
modprobe intel_pmc_core 2>/dev/null

echo "Ne touche plus à rien : la mesure démarre dans 20 s et dure 30 s."
sleep 20

python3 -I - "$DBG" <<'EOF' >"$OUT" 2>&1
import glob, sys, time
DBG = sys.argv[1]
T = 30

def tasks():
    d = {}
    for p in glob.glob('/proc/[0-9]*/task/[0-9]*'):
        try:
            s = open(p + '/status').read()
            c = int(s.split('voluntary_ctxt_switches:')[1].split()[0]) + \
                int(s.split('nonvoluntary_ctxt_switches:')[1].split()[0])
            pid = p.split('/')[2]
            d[p] = (c, open(f'/proc/{pid}/comm').read().strip(), open(p + '/comm').read().strip())
        except Exception:
            pass
    return d

def irqs():
    d = {}
    for l in open('/proc/interrupts').read().splitlines()[1:]:
        f = l.split()
        n, tot, i = f[0], 0, 1
        while i < len(f) and f[i].isdigit():
            tot += int(f[i]); i += 1
        d[n] = (tot, ' '.join(f[i:])[-50:])
    return d

def pkg():
    return {l.split(':')[0].strip(): int(l.split(':')[1]) for l in open(DBG + '/pmc_core/package_cstate_show')}

t0, i0, p0 = tasks(), irqs(), pkg()
e0 = int(open('/sys/class/powercap/intel-rapl:0/energy_uj').read())
time.sleep(T)
t1, i1, p1 = tasks(), irqs(), pkg()
e1 = int(open('/sys/class/powercap/intel-rapl:0/energy_uj').read())

print(f"Puissance package CPU : {(e1 - e0) / T / 1e6:.2f} W")
for k in p1:
    v = (p1[k] - p0.get(k, 0)) / (T * 1e4)
    if v >= 0.1:
        print(f"  {k:12s} {v:5.1f} %")

print("\n=== Interruptions (par seconde)")
r = sorted(((i1[k][0] - i0[k][0]) / T, k, i1[k][1]) for k in i1 if k in i0)
print(f"total {sum(x[0] for x in r):.0f}/s")
for x in sorted(r, reverse=True)[:15]:
    print(f"{x[0]:8.1f}  {x[1]:6s} {x[2]}")

print("\n=== Réveils par processus / thread (par seconde)")
agg = {}
for k, (c, pn, tn) in t1.items():
    if k in t0 and c > t0[k][0]:
        agg[(pn, tn)] = agg.get((pn, tn), 0) + (c - t0[k][0]) / T
print(f"total {sum(agg.values()):.0f}/s")
for (pn, tn), x in sorted(agg.items(), key=lambda i: -i[1])[:30]:
    print(f"{x:8.1f}  {pn:22s} {tn}")
EOF

{
  echo; echo "=== Générateur aléatoire matériel"
  echo "actuel : $(cat /sys/class/misc/hw_random/rng_current 2>/dev/null)  dispo : $(cat /sys/class/misc/hw_random/rng_available 2>/dev/null)"
  echo "=== Noyau"; uname -r; zgrep -E '^CONFIG_(HZ|NO_HZ_IDLE|NO_HZ_FULL|RCU_LAZY|RCU_NOCB_CPU)=' /proc/config.gz
} >>"$OUT"

[ -n "$proprio" ] && chown "$proprio:" "$OUT"
cat "$OUT"
echo "Terminé : $OUT"
