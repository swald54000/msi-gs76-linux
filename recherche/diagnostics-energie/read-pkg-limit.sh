#!/usr/bin/env bash
# shellcheck disable=SC1091
# Outil de recherche (root). Lit la limite d'état C du package
# (MSR_PKG_CST_CONFIG_CONTROL, 0xE2) sur chaque CPU. Lecture seule.
# Écrit ./pkg-limit.txt (dossier courant).
set -euo pipefail
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ici/../../lib/commun.sh"
exiger_root
modprobe msr
OUT="$PWD/pkg-limit.txt"
proprio="$(utilisateur_cible 2>/dev/null || true)"
python3 -I - <<'EOF' | tee "$OUT"
import glob, os, struct
names = {0: "PC0/PC1", 1: "PC2", 2: "PC6 (sans rétention)", 3: "PC6 (rétention)",
         4: "PC7", 5: "PC7s", 6: "PC8", 7: "PC9", 8: "PC10", 15: "aucune limite"}
for path in sorted(glob.glob("/dev/cpu/*/msr"), key=lambda p: int(p.split("/")[3])):
    fd = os.open(path, os.O_RDONLY)
    v = struct.unpack("<Q", os.pread(fd, 8, 0xE2))[0]
    os.close(fd)
    lim = v & 0xF
    print(f"cpu{path.split('/')[3]:>2}  0xE2={v:#010x}  limite={lim} ({names.get(lim, '?')})  "
          f"verrouillé={'oui' if v >> 15 & 1 else 'non'}")
EOF
if [ -n "$proprio" ]; then chown "$proprio:" "$OUT"; fi
