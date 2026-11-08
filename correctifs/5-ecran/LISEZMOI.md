# Correctif 5 : PSR et fréquence de l'écran selon l'alimentation

Ce correctif a deux parties indépendantes.

## Le problème

- **PSR** : le VBT des MSI désactive le Panel Self Refresh (PSR) de la dalle interne.
  Sans PSR, le processeur ne descend pas dans ses états de repos profonds à l'inactivité.
- **Fréquence** : à 360 Hz, le temps d'établissement du PSR de la dalle (330 us) ne tient
  pas ; à 60 Hz, i915 peut l'utiliser. Mesuré : environ 2,9 W -> 1,45 W au repos.

## Ce qui est installé

- `--psr` : `/etc/systemd/system/i915-psr-force.service` (activé et démarré). Il écrit `0x3`
  dans `i915_edp_psr_debug` de debugfs pour autoriser le PSR1 ; à l'arrêt il remet `0x0`.
  Refusé si le module `i915` n'est pas chargé.
- `--frequence` : `/usr/local/bin/edp-refresh-auto` et l'unité utilisateur
  `/etc/systemd/user/edp-refresh-auto.service`, activée pour tous les utilisateurs
  (`systemctl --global enable`). Le script règle la dalle `eDP*` sur la fréquence la plus
  basse sur batterie, la plus haute sur secteur, à chaud (la configuration de Hyprland n'est
  pas modifiée) et à nouveau après chaque rechargement de configuration. Il demande
  `hyprctl`, `jq`, `socat` et UPower (`busctl`, `gdbus`). Il démarre à la prochaine
  ouverture de session.

Sans option, les deux parties sont installées. Un fichier préexistant de même nom est
sauvegardé dans `/var/lib/msi-gs76-linux/sauvegardes/`.

## Hyprland 0.56 minimum (`--frequence`)

La version est lue avec `hyprctl version -j`. Lancé sous `sudo`, `hyprctl` peut ne pas
atteindre votre session : l'installateur se rabat alors sur `pacman -Q hyprland`. Si la
version est inférieure à 0.56 ou introuvable, il refuse, sauf avec `--force`.

## Utilisation

    sudo ./installer.sh [--psr] [--frequence] [--force]
    ./verifier.sh        # sans privilèges ; code 0 sain, 1 rien d'installé, 2 défaut

`verifier.sh` affiche une ligne par partie (`OK`, `ABSENT` ou `DÉFAUT`) ; une partie non
installée n'est un défaut que si l'autre l'est. `--force` contourne la vérification du
matériel (GS76, firmware 17M1) et celle de la version de Hyprland.

## Désinstallation

    sudo ./desinstaller.sh

Désactive les deux services, retire (ou restaure) les trois fichiers. Les sessions déjà
ouvertes gardent le script en cours d'exécution jusqu'à leur fermeture.
