# Correctif 4 : cache batterie et rafraîchissement en tâche de fond

## Le problème

Sur les MSI, la méthode ACPI `_BST` du BIOS met environ 114 ms à répondre. Chaque
lecture de l'état de la batterie (widget, gestionnaire d'énergie, jeu) bloque donc
brièvement, ce qui provoque des saccades.

## Ce qui est installé

- Le noyau garde l'état de la batterie en cache (`/sys/module/battery/parameters/cache_time`).
  Le cache passe à 5 minutes (`CACHE_BATTERIE_MS`, 300000 par défaut), via
  `/etc/tmpfiles.d/battery-cache.conf` pour qu'il survive au redémarrage.
- `/usr/local/bin/battery-refresh` : ramène brièvement le cache à 1 ms, lit l'état
  (ce qui force la lecture lente), puis remet la valeur. C'est ce service, et non un
  jeu, qui paie le coût.
- `battery-refresh.service` et `battery-refresh.timer` (`/etc/systemd/system/`) : le
  minuteur lance le service toutes les `RAFRAICHISSEMENT` secondes (30 par défaut).
- `/etc/msi-gs76-linux/batterie.conf` : ligne `BATTERIE=/sys/class/power_supply/BAT0`,
  chemin de la batterie détectée par l'installateur (ni `AC`, ni périphérique comme une souris).

Les fichiers préexistants de même nom sont sauvegardés dans
`/var/lib/msi-gs76-linux/sauvegardes/`, ainsi que la valeur d'origine de `cache_time`.

## Utilisation

    sudo bash installer.sh [--force]
    sudo RAFRAICHISSEMENT=60 CACHE_BATTERIE_MS=120000 bash installer.sh
    bash verifier.sh        # sans privilèges ; code 0 sain, 1 absent, 2 défaut

Les deux variables doivent être des entiers strictement positifs, sinon l'installateur
refuse avant tout changement. `--force` contourne la vérification du matériel
(GS76, firmware 17M1). Relancer l'installateur ne crée aucun doublon.

## Désinstallation

    sudo bash desinstaller.sh

Désactive le minuteur, retire (ou restaure) les fichiers et remet la valeur d'origine
de `cache_time`.
