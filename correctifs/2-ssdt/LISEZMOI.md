# Correctif 2 : SSDT ACPI pour le GS76

## Le problème

Le BIOS du MSI GS76 (11UH) a deux défauts de description ACPI :

- `\_SB.IETM._OSC` référence un objet `\_TZ.ETMD` que le BIOS ne définit jamais :
  la méthode échoue (`AE_NOT_FOUND`) et les réglages Intel DTT n'atteignent pas `thermald`.
- Le pavé tactile I2C-HID est aussi détecté comme souris PS/2 (`SynPS/2`), en double.

## Ce qui est installé

Une table SSDT « en ajout seul », `ssdt-gs76.aml` (source lisible : `ssdt-gs76.asl`) :
elle définit `\_TZ.ETMD` et positionne `PS2M.I2CT` à 1, ce qui masque l'alias PS/2.
Elle ne contient aucune adresse mémoire du firmware, donc elle reste valable si le
BIOS déplace ses régions ACPI (ce qui cassait l'ancienne surcharge complète de la DSDT).

- `/etc/initcpio/acpi_override/ssdt-gs76.aml` : la table, injectée très tôt au démarrage
  par le hook `acpi_override` de mkinitcpio ;
- `/etc/mkinitcpio.conf.d/zz-acpi-override.conf` : contient `HOOKS+=(acpi_override)` ;
- les initramfs sont reconstruits (`limine-mkinitcpio` s'il existe, sinon `mkinitcpio -P`).

Si un fichier de même nom existait déjà, il est sauvegardé dans
`/var/lib/msi-gs76-linux/sauvegardes/` et remis par la désinstallation.

## Utilisation

    sudo bash installer.sh [--force]
    bash verifier.sh        # sans privilèges ; code 0 sain, 1 absent, 2 défaut

`--force` contourne la vérification du matériel (GS76, firmware 17M1). L'installateur
refuse de continuer si l'ancienne surcharge complète `dsdt.aml` est encore présente
dans `/etc/initcpio/acpi_override/` : retirez-la d'abord.

**Redémarrez** après l'installation : la table n'est lue qu'au démarrage.

## Vérification sans privilèges

`verifier.sh` ne demande pas root, or les tables ACPI (`/sys/firmware/acpi/tables/`)
sont réservées à root. Il combine donc les preuves disponibles :

- les deux fichiers installés (sinon : `ABSENT`) ;
- le journal du noyau (`journalctl -k -b`) s'il est lisible : `GS76FIX` doit y figurer ;
  illisible, une ligne `INFO` le signale et ce n'est pas un défaut ;
- l'absence d'un périphérique `SynPS/2` dans `/proc/bus/input/devices` ;
- les tables SSDT chargées, si elles sont lisibles (en root) : `GS76FIX` doit y figurer.

Code 2 (`DÉFAUT`) : installée mais une preuve montre qu'elle n'est pas chargée.
Sans preuve positive possible, la sortie le dit (« chargement non prouvé »).

## Retour arrière

    sudo bash desinstaller.sh

Retire la table, et `zz-acpi-override.conf` seulement si aucune autre table `.aml`
ne reste dans `acpi_override`, puis reconstruit les initramfs. Si le système ne démarre
plus correctement après l'installation, choisissez dans le menu de démarrage Limine
l'**instantané** Snapper « avant SSDT GS76 (acpi_override) » pris par l'installateur
(si `snapper` est présent) : il démarre sur l'état d'avant, sans la table.

## Recompiler la table

    iasl ssdt-gs76.asl

produit `ssdt-gs76.aml` (outil `iasl`, paquet `acpica`). Le test du dépôt vérifie que
le `.aml` versionné est identique à la compilation du `.asl`.
