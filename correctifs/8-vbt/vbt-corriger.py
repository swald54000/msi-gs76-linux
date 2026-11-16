#!/usr/bin/env python3
"""VBT corrigée pour la dalle AUO 0xE295 du GS76 Stealth 11UH.

La VBT de MSI ne déclare pas cette dalle : son identifiant n'est dans aucune des 16 entrées,
i915 retombe donc sur l'entrée 0 (fallback_get_panel_type), dont les bits PSR et DRRS du bloc 44
(struct bdb_lfp_power) sont à 0. Ce script met ces deux bits à 1 pour l'entrée 0, rien d'autre,
et compense l'octet de somme de contrôle de l'en-tête (somme de tous les octets = 0 modulo 256).
Structures : drivers/gpu/drm/i915/display/intel_vbt_defs.h (noyau 7.3).

usage : vbt-corriger.py <vbt d'origine> <vbt corrigée>
        vbt-corriger.py --verifier <vbt>      code 0 si la VBT est valide et déjà corrigée"""
import struct
import sys

PANNEAU = 0          # entrée de repli utilisée par i915
BLOC_LFP_POWER = 44
# struct bdb_lfp_power : features (1) + als[5] (20) + lace (1) + dpst (2), puis psr (2), drrs (2)
DECALAGE_PSR, DECALAGE_DRRS = 24, 26


class Invalide(Exception):
    pass


def analyser(d):
    """Retourne (taille de la VBT, décalage du bloc 44) ou lève Invalide."""
    if len(d) < 48 or d[:4] != b'$VBT':
        raise Invalide('signature $VBT absente')
    taille = struct.unpack_from('<H', d, 24)[0]
    bdb = struct.unpack_from('<I', d, 28)[0]
    if taille > len(d) or bdb + 22 > taille:
        raise Invalide('en-tête incohérent (tailles)')
    if d[bdb:bdb + 16] != b'BIOS_DATA_BLOCK ':
        raise Invalide('BDB absente')
    version, entete, taille_bdb = struct.unpack_from('<HHH', d, bdb + 16)
    if version < 228:
        raise Invalide('BDB version %d : les bits PSR/DRRS par panneau existent depuis la 228' % version)
    if sum(d[:taille]) % 256 != 0:
        raise Invalide('somme de contrôle incorrecte')
    p, fin = bdb + entete, min(bdb + taille_bdb, taille)
    while p + 3 <= fin:
        ident, longueur = d[p], struct.unpack_from('<H', d, p + 1)[0]
        if ident == BLOC_LFP_POWER:
            if longueur < DECALAGE_DRRS + 2:
                raise Invalide('bloc 44 trop court')
            return taille, p + 3
        p += 3 + longueur
    raise Invalide('bloc 44 (lfp_power) absent')


def bits(d, bloc):
    psr = struct.unpack_from('<H', d, bloc + DECALAGE_PSR)[0]
    drrs = struct.unpack_from('<H', d, bloc + DECALAGE_DRRS)[0]
    return psr, drrs


def corriger(d):
    d = bytearray(d)
    taille, bloc = analyser(d)
    psr, drrs = bits(d, bloc)
    struct.pack_into('<H', d, bloc + DECALAGE_PSR, psr | 1 << PANNEAU)
    struct.pack_into('<H', d, bloc + DECALAGE_DRRS, drrs | 1 << PANNEAU)
    d = d[:taille]
    d[26] = (d[26] - sum(d)) % 256          # vbt_header.vbt_checksum
    return bytes(d), (psr, drrs), bits(d, bloc)


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == '--verifier':
            d = open(argv[2], 'rb').read()
            _, bloc = analyser(d)
            psr, drrs = bits(d, bloc)
            if psr >> PANNEAU & 1 and drrs >> PANNEAU & 1:
                return 0
            print('VBT non corrigée : psr=%#06x drrs=%#06x' % (psr, drrs), file=sys.stderr)
            return 1
        if len(argv) != 3:
            print(__doc__, file=sys.stderr)
            return 2
        sortie, avant, apres = corriger(open(argv[1], 'rb').read())
        open(argv[2], 'wb').write(sortie)
        print('psr %#06x -> %#06x, drrs %#06x -> %#06x, %d octets' % (avant[0], apres[0], avant[1], apres[1], len(sortie)))
        return 0
    except (Invalide, OSError) as e:
        print('VBT refusée : %s' % e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
