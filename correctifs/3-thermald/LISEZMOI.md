# Correctif 3 : thermald attend RAPL

**Ce correctif ne sert qu'avec le correctif 2 (SSDT).** Sans lui, il est inutile
(mais inoffensif).

## Le problème

`thermald` ne lit l'arbre `powercap` RAPL qu'à son démarrage. Une fois l'alias PS/2
du pavé tactile masqué par le correctif 2, l'espace utilisateur démarre environ 0,5 s
plus tôt et peut devancer le chargement des modules `intel_rapl_*` : `thermald`
journalise alors « NO RAPL sysfs present » et travaille sans RAPL.

## Ce qui est installé

Un complément systemd, `/etc/systemd/system/thermald.service.d/wait-rapl.conf`, qui
ajoute à `thermald.service` un `ExecStartPre` : il attend jusqu'à 5 s que
`/sys/class/powercap/intel-rapl:0` apparaisse, puis laisse démarrer `thermald`
dans tous les cas. L'installateur lance `systemctl daemon-reload` ; le complément
s'applique au prochain démarrage du service. Un éventuel fichier de même nom est
sauvegardé dans `/var/lib/msi-gs76-linux/sauvegardes/`.

## Utilisation

    sudo bash installer.sh [--force]
    bash verifier.sh        # sans privilèges ; code 0 sain, 1 absent, 2 défaut

`--force` contourne la vérification du matériel (GS76, firmware 17M1).

## Désinstallation

    sudo bash desinstaller.sh

Retire le complément (ou remet l'ancien), supprime le dossier `thermald.service.d`
s'il est vide, puis lance `systemctl daemon-reload`.
