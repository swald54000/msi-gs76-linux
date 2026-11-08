# Correctif 1 : pilote msi-ec pour le GS76

## Le problème

Le pilote `msi-ec` d'origine ne gère pas correctement le MSI GS76 (firmware 17M1) :
pas de courbe de ventilateur (`cpu/fan_curve`), et les réglages (mode ventilateur,
seuil de charge) ne sont accessibles qu'à root. Ce correctif installe via DKMS
une version corrigée issue d'un fork public, et ouvre les réglages à un groupe dédié.

## Ce qui est installé

- Le pilote du fork `https://github.com/swald54000/msi-ec.git`, commit figé
  `4b72e41bdeb6d0c9949dd3b16a5dff1a6956ff97`, dans `/usr/src/msi-ec-gs76.4b72e41`,
  compilé par DKMS pour chaque noyau ayant ses en-têtes. Un noyau sans en-têtes est
  signalé « ignoré » : installez ses en-têtes puis relancez l'installateur.
- La règle udev `/etc/udev/rules.d/99-msi-ec.rules` : au chargement du pilote, elle
  donne `shift_mode`, `fan_mode` et `cooler_boost` au groupe `msi-ec` (écriture
  autorisée) et fixe le seuil de charge de la batterie.
- Le groupe système `msi-ec`, auquel l'utilisateur qui lance `sudo` est ajouté.
- Dans `/var/lib/msi-gs76-linux/` : la version DKMS de msi-ec présente avant
  l'installation (`pilote-precedent`) et la sauvegarde de l'ancienne règle udev.

## Utilisation

    sudo ./installer.sh [--force]
    ./verifier.sh        # sans privilèges ; code 0 sain, 1 absent, 2 défaut

`--force` contourne la vérification du matériel (GS76, firmware 17M1). À la fin,
l'installateur lance `verifier.sh` et affiche son résultat, à titre indicatif : il ne
change pas le code de sortie de l'installation. Le verifier indique aussi la version du
module chargé.

## Variables

| Variable | Défaut | Rôle |
|---|---|---|
| `SEUIL_CHARGE` | `80` | Seuil de charge, de 50 à 100 ; autre valeur : refus avant toute action |
| `MSI_EC_DEPOT` | dépôt du fork | Dépôt git du pilote |
| `MSI_EC_REF` | commit figé | Commit à installer, en hexadécimal minuscule (7 à 40 caractères, sinon refus avant toute action) ; la version DKMS est `gs76.` + 7 premiers caractères |
| `MSI_EC_NOYAUX` | tous | Liste de noyaux (séparés par des espaces) à traiter |

Exemple : `sudo SEUIL_CHARGE=70 ./installer.sh`.

## Reconnexion nécessaire

L'appartenance au groupe `msi-ec` ne prend effet qu'à la prochaine connexion :
**déconnectez-vous puis reconnectez-vous** (ou redémarrez) après l'installation.
D'ici là, les réglages restent refusés.

## Désinstallation

    sudo ./desinstaller.sh

Retire le pilote du fork, réinstalle la version précédente si ses sources sont
encore dans `/usr/src`, restaure la règle udev d'origine, retire l'utilisateur qui a
lancé `sudo` du groupe `msi-ec` (la déconnexion/reconnexion applique le retrait) et
supprime ce groupe s'il n'a plus aucun membre. Relancer l'installateur est sans danger :
aucune ligne en double, aucune sauvegarde écrasée.

Attention : si une relance de l'installateur échoue, le retour arrière remet le
pilote présent avant la **première** installation (celui mémorisé dans
`pilote-precedent`), pas l'installation précédente du fork.
