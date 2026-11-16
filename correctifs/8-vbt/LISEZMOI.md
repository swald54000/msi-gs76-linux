# Correctif 8 : VBT corrigée pour la dalle interne

## Le problème

La VBT (table de configuration vidéo du BIOS) de MSI ne déclare pas la dalle interne
AUO `0xE295` : son identifiant n'est dans aucune des 16 entrées (la seule dalle AUO
listée est la `0xDE95`). La VBT demande pourtant une recherche par identifiant
(`panel_type` = 255). Le pilote `i915` retombe donc sur l'entrée 0
(`fallback_get_panel_type`), dont les bits PSR et DRRS du bloc 44 sont à 0.

Conséquences, lues dans le code du pilote et constatées sur la machine :

- PSR refusé (« PSR disabled by flag ») : `psr_global_enabled()` renvoie la valeur de la VBT.
- DRRS « static » seulement : pas de retour automatique à 60 Hz quand l'image est fixe.

Les réglages PSR, les délais d'alimentation et le rétroéclairage sont identiques pour
les 16 entrées : seuls ces deux bits distinguent l'entrée 0 des entrées ordinaires.

## Ce qui est installé

- `/usr/lib/firmware/updates/gs76/vbt-auo-e295.bin` : la VBT **de la machine**, lue dans
  `debugfs`, où `vbt-corriger.py` met à 1 les bits PSR et DRRS de l'entrée 0 et compense
  l'octet de somme de contrôle. Trois octets changent. Aucune VBT n'est distribuée ici.
- `/etc/modprobe.d/gs76-vbt.conf` : `options i915 vbt_firmware=gs76/vbt-auo-e295.bin`.
- `/etc/mkinitcpio.conf.d/zz-gs76-vbt.conf` : ajoute le fichier à l'initramfs, d'où
  `i915` peut être chargé. Les initramfs sont reconstruits.

Un instantané est pris avant l'installation ; les fichiers préexistants sont sauvegardés
dans `/var/lib/msi-gs76-linux/sauvegardes/`. **Prend effet au prochain démarrage.**

## Effet mesuré (16 novembre 2026, sur batterie, écran interne immobile)

| Mode | Avant | Après |
|---|---|---|
| 60 Hz | PSR « disabled by flag » | PSR actif sans forçage, en veille sur 39 relevés sur 60 |
| 360 Hz | DRRS « static », inactif | DRRS « seamless », en basse fréquence sur 58 relevés sur 60 |

Pas de scintillement constaté. À 360 Hz le PSR reste impossible : le temps
d'établissement de la dalle (330 us) ne tient pas dans l'intervalle de retour vertical.

Le gain en watts n'est **pas** mesuré : la puissance du processeur est la même dans les
deux cas (ce compteur ne voit pas la dalle) et une machine virtuelle tournait pendant
l'essai. Il reste à mesurer la décharge de la batterie, machine au repos.

Le PSR et le DRRS ne jouent que si rien ne redessine l'écran interne : une fenêtre
animée, ou une icône animée dans la barre, les empêche en permanence.

## Utilisation

    sudo ./installer.sh [--force]
    ./verifier.sh        # sans privilèges ; code 0 sain, 1 absent, 2 défaut

L'installateur refuse une autre dalle que l'AUO `0xE295` (identifiant EDID `06af95e2`),
sauf avec `--force`, qui contourne aussi la vérification du matériel. Il demande
`python3`. Il peut être relancé : la VBT en service étant alors déjà corrigée, il produit
le même fichier.

`verifier.sh` s'appuie sur le journal du noyau ; lancé en root, il contrôle aussi que le
DRRS retenu est « seamless ».

## Désinstallation

    sudo ./desinstaller.sh

Puis redémarrer. Si l'écran interne pose problème au démarrage, choisir une entrée
« Snapshots » dans le menu Limine avant de désinstaller.

## Limites

- Le paramètre `vbt_firmware` est déclaré « unsafe » par le pilote : le noyau est marqué
  *tainted* (« Setting dangerous option vbt_firmware - tainting kernel »).
- Le correctif vaut pour la VBT du BIOS `E17M1IMS.119`. Après une mise à jour du BIOS,
  désinstaller, redémarrer, puis réinstaller pour repartir de la nouvelle VBT.
- Avec ce correctif, le PSR forcé du correctif 5 (`i915-psr-force`) devient redondant :
  le PSR s'active seul à 60 Hz. La bascule de fréquence selon l'alimentation du même
  correctif reste utile, puisque le PSR n'existe qu'à 60 Hz.
