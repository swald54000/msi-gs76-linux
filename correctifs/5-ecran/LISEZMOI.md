# Correctif 5 : fréquence de l'écran selon l'alimentation

## Le problème

À 360 Hz, le temps d'établissement du PSR de la dalle interne (330 us) ne tient pas : le
PSR est impossible et le processeur ne descend pas dans ses états de repos profonds à
l'inactivité. À 60 Hz, `i915` peut l'utiliser. Mesuré : environ 2,9 W -> 1,45 W au repos.

Le PSR lui-même vient du **correctif 8** (VBT corrigée) : sans lui, le pilote le refuse
quelle que soit la fréquence.

## Ce qui est installé

`/usr/local/bin/edp-refresh-auto` et l'unité utilisateur
`/etc/systemd/user/edp-refresh-auto.service`, activée pour tous les utilisateurs
(`systemctl --global enable`). Le script règle la dalle `eDP*` sur la fréquence la plus
basse sur batterie, la plus haute sur secteur, à chaud (la configuration de Hyprland n'est
pas modifiée) et à nouveau après chaque rechargement de configuration. Il demande
`hyprctl`, `jq`, `socat` et UPower (`busctl`, `gdbus`). Il démarre à la prochaine
ouverture de session.

Un fichier préexistant de même nom est sauvegardé dans
`/var/lib/msi-gs76-linux/sauvegardes/`.

La bascule suit UPower, qui n'annonce le passage sur batterie qu'une trentaine de
secondes après le débranchement (35 s mesurées).

## L'ancien PSR forcé

Les versions précédentes de ce correctif installaient aussi `i915-psr-force.service`,
qui forçait le PSR par `debugfs` parce que la VBT de MSI le désactive pour cette dalle.
Le correctif 8 traite la cause : avec la VBT corrigée, le PSR s'active seul à 60 Hz
(vérifié sans le forçage). Le service est donc supprimé :

- l'installateur le désactive et le retire s'il le trouve ;
- `verifier.sh` signale un défaut tant qu'il est présent ;
- l'option `--psr` est refusée et renvoie au correctif 8.

## Hyprland 0.56 minimum

La version est lue avec `hyprctl version -j`. Lancé sous `sudo`, `hyprctl` peut ne pas
atteindre votre session : l'installateur se rabat alors sur `pacman -Q hyprland`. Si la
version est inférieure à 0.56 ou introuvable, il refuse, sauf avec `--force`.

## Utilisation

    sudo ./installer.sh [--force]
    ./verifier.sh        # sans privilèges ; code 0 sain, 1 rien d'installé, 2 défaut

À la fin, l'installateur lance `verifier.sh` et affiche son résultat, à titre indicatif :
il ne change pas le code de sortie de l'installation.

`--force` contourne la vérification du matériel (GS76, firmware 17M1) et celle de la
version de Hyprland. `--frequence` reste acceptée, sans effet.

## Désinstallation

    sudo ./desinstaller.sh

Désactive l'unité utilisateur, retire (ou restaure) les deux fichiers, et retire l'ancien
service de PSR forcé s'il est encore là. Les sessions déjà ouvertes gardent le script en
cours d'exécution jusqu'à leur fermeture.
