# Correctif 7 : limites de puissance après hibernation

## Le problème

Au retour d'hibernation, le plafond de puissance court terme du processeur (PL2) vaut
120 W au lieu de la valeur du mode en cours (64 W en `comfort`). Il y reste jusqu'au
prochain changement de mode. Constaté le 16 novembre 2026 : 45/120 W au réveil, mode
`comfort`.

Trois maillons, chacun lu dans le code :

- **BIOS** : la valeur d'usine de PL2 est 120 W (`CpuSetup`, « Power Limit 2 » = 120000 mW).
  Le firmware la reprogramme à chaque démarrage, y compris celui qui précède la reprise.
- **Noyau** : `rapl_pm_callback` (`drivers/powercap/intel_rapl_common.c`) ne sauvegarde et
  ne restaure les limites que pour la veille (`PM_SUSPEND_PREPARE`, `PM_POST_SUSPEND`),
  pas pour l'hibernation.
- **thermald** (2.5.13) : aucun code de reprise, et `update_engine_state()` sort dès que
  la cible n'a pas changé. Réécrire le même mode dans `shift_mode` ne fait donc rien.

Pourquoi PL1 reste à 45 W alors que sa valeur d'usine est aussi 120 W n'est pas établi.

## Ce qui est installé

Une unité systemd, `/etc/systemd/system/thermald-apres-hibernation.service`, activée
pour `hibernate.target`, `hybrid-sleep.target` et `suspend-then-hibernate.target`. Au
retour, elle lance `systemctl try-restart thermald.service` : thermald redémarre, évalue
de nouveau son palier et réécrit les limites. Rien n'est écrit dans l'EC.

Mesuré en simulant l'état d'après-hibernation (PL2 forcé à 120 W) : thermald seul ne
corrige rien en 6 s ; relancé, il rétablit 45/64 W en 4 s. Vérifié ensuite sur un cycle
d'hibernation réel (16 novembre 2026) : l'unité se déclenche à la sortie d'hibernation et les
limites sont à 45/64 W treize secondes après.

La veille simple n'est pas concernée : le noyau y restaure déjà les limites.

## Utilisation

    sudo ./installer.sh [--force]
    ./verifier.sh        # sans privilèges ; code 0 sain, 1 absent, 2 défaut

À la fin, l'installateur lance `verifier.sh` et affiche son résultat, à titre indicatif :
il ne change pas le code de sortie de l'installation.

`--force` contourne la vérification du matériel (GS76, firmware 17M1).

## Désinstallation

    sudo ./desinstaller.sh

## Limites

- thermald relancé perd son état interne ; il le reconstruit en quelques secondes.
- Le vrai défaut est dans le noyau. Un correctif en amont (traiter aussi
  `PM_HIBERNATION_PREPARE` et `PM_POST_HIBERNATION` dans `rapl_pm_callback`) rendrait
  cette unité inutile.
