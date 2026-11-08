# MSI GS76 Stealth sous Linux

*English version: [README.md](README.md).*

Correctifs pour le **MSI GS76 Stealth 11UH** sous Arch Linux, testés sur
[Omarchy](https://omarchy.org) : courbe de ventilateur et accès aux réglages, deux bugs
ACPI du BIOS, une requête batterie lente qui fait saccader les jeux, et la consommation
au repos de l'écran interne. Chaque correctif est indépendant, a son installateur, son
vérificateur et son désinstallateur, et peut être annulé.

- Six correctifs dans `correctifs/`, chacun avec un `LISEZMOI.md` qui explique le
  problème et ce qui est installé exactement.
- Une partie recherche dans [`recherche/`](recherche/README.fr.md) : les outils, les
  mesures brutes et les questions ouvertes derrière les correctifs. Rien n'y est
  nécessaire pour les utiliser.
- `verifier-tout.sh` : un tableau qui vérifie tous les correctifs.

## Matériel visé

| | |
|---|---|
| Modèle | MSI GS76 Stealth 11UH |
| BIOS | `E17M1IMS.119` |
| Firmware EC | `17M1EMS1.113` |

Les correctifs ont été mesurés sur cette machine exacte. Les installateurs acceptent une
machine dont le `product_name` DMI contient `GS76` **et** dont le firmware est `17M1`
(`fw_version` de msi-ec commençant par `17M1`, sinon `bios_version` DMI commençant par
`E17M1`). Ils refusent toute autre machine sauf avec `--force`. D'autres variantes du
GS76 (par exemple le 11UG) peuvent fonctionner, mais rien ici ne le prouve.

## Les six correctifs

| N° | Dossier | Problème | Effet mesuré | Risque |
|---|---|---|---|---|
| 1 | `1-pilote-msi-ec` | Le pilote `msi-ec` d'origine n'a pas de courbe de ventilateur (`cpu/fan_curve`) pour le GS76, et le mode des ventilateurs et le seuil de charge ne sont réglables que par root | Installe un pilote corrigé via DKMS et ouvre les réglages au groupe `msi-ec` ; pas de chiffre | Faible : remplace le module DKMS `msi-ec`, l'ancien est remis à la désinstallation |
| 2 | `2-ssdt` | Bugs ACPI du BIOS : `\_TZ.ETMD` n'est jamais défini, donc `_OSC` échoue et les réglages Intel DTT n'atteignent pas `thermald` ; le pavé tactile I2C apparaît aussi comme souris `SynPS/2` | Les erreurs `_OSC` disparaissent et l'alias PS/2 aussi (voir la [recherche](recherche/README.fr.md), section 2) ; pas de chiffre de performance | **Moyen : agit au démarrage** (SSDT en ajout seul, injectée par l'initramfs). Si le système se comporte mal, choisir l'instantané Snapper « avant SSDT GS76 (acpi_override) » dans le menu de démarrage Limine |
| 3 | `3-thermald` | Après le correctif 2, l'espace utilisateur démarre environ 0,5 s plus tôt et `thermald` peut devancer `intel_rapl_*` et travailler sans RAPL | `thermald` attend RAPL jusqu'à 5 s ; pas de chiffre. **Utile seulement avec le correctif 2** | Faible : un complément systemd |
| 4 | `4-batterie` | La méthode `_BST` du BIOS prend environ 114 ms, donc chaque lecture de la batterie fait saccader (widget, gestionnaire d'énergie, jeux) | Un cache noyau de 5 minutes et un rafraîchissement en tâche de fond écartent ce coût des jeux ; pas de chiffre pour le cache lui-même | Faible : une entrée tmpfiles, un minuteur systemd, `cache_time` d'origine remis à la désinstallation |
| 5 | `5-ecran` | Le VBT des MSI désactive le Panel Self Refresh, et à 360 Hz le temps d'établissement du PSR de la dalle (330 us) est trop long, donc le processeur n'atteint jamais les états de repos profonds | Environ 2,9 W puis 1,45 W au repos (puissance du processeur, 60 Hz avec PSR forcé) | Faible à moyen : écrit dans debugfs d'i915 au démarrage ; le changement de fréquence demande Hyprland 0.56 ou plus |
| 6 | `6-widget-ventilateurs` | Aucun moyen de voir ou de changer le mode des ventilateurs depuis la barre | Un widget de barre (plugin Omarchy, dépôt séparé) ; demande le correctif 1 | Faible : un plugin utilisateur |

Le détail, les variables (`SEUIL_CHARGE`, `RAFRAICHISSEMENT`, ...) et les notes de
désinstallation sont dans le `LISEZMOI.md` de chaque dossier.

## Prérequis

- Arch Linux, `bash`, `git`, systemd
- Omarchy : pour la partie fréquence du correctif 5 et pour le correctif 6
- `dkms` et les en-têtes de chaque noyau installé (correctif 1)
- `mkinitcpio` (correctif 2)
- `column` d'util-linux (pour `verifier-tout.sh`)
- `jq` facultatif (la partie fréquence du correctif 5 demande aussi `socat` et UPower,
  voir sa notice)

## Ordre conseillé

1. **Correctif 1** (pilote), puis **fermer et rouvrir la session** : l'appartenance au
   groupe ne prend effet qu'à la connexion suivante.
2. **Correctif 2** (SSDT), puis **redémarrer**. Ensuite le **correctif 3**.
3. **Correctif 4** (batterie) et **correctif 5** (écran) ; ils sont indépendants des autres.
4. **Correctif 6** (widget), une fois le correctif 1 actif.

## Utilisation

Depuis le dossier du correctif voulu :

    cd correctifs/1-pilote-msi-ec
    sudo ./installer.sh        # installer (--force pour passer la vérification du matériel)
    ./verifier.sh              # vérifier, sans privilèges
    sudo ./desinstaller.sh     # annuler

`verifier.sh` affiche `OK`, `ABSENT` ou `DÉFAUT <détail>` et sort avec le code 0 (sain),
1 (non installé) ou 2 (défaut). Les installateurs et désinstallateurs sont idempotents et
gardent une sauvegarde de ce qu'ils remplacent dans `/var/lib/msi-gs76-linux/`.

Le correctif 6 s'installe par Omarchy :

    omarchy plugin add https://github.com/swald54000/omarchy-msi-fans.git --enable

et se retire avec `omarchy plugin remove swald.fans` ; son `./verifier.sh` fonctionne
comme les autres.

Pour tout vérifier d'un coup, sans privilèges :

    ./verifier-tout.sh

Il lance chaque `verifier.sh` et affiche une ligne par correctif : sain, non installé ou
en défaut.

## Retour arrière

Chaque correctif a un `sudo ./desinstaller.sh` qui remet ce que l'installateur a
sauvegardé. Le correctif 2 agit au démarrage : si le système ne démarre plus
correctement, choisir l'instantané Snapper « avant SSDT GS76 (acpi_override) » (pris par
l'installateur si `snapper` est présent) dans le menu de démarrage Limine, puis lancer
son désinstallateur.

## Limites connues

- Le ventilateur auxiliaire (le troisième) sous charge GPU n'a **pas été vérifié** ; la
  recherche documente ce que l'on en sait (sources communautaires seulement).
- L'échec d'énumération du clavier USB (erreur -71) n'existe que dans
  [`recherche/`](recherche/README.fr.md), comme **hypothèse non confirmée** ; ce n'est
  pas un correctif.
- Les correctifs visent ce modèle et ce firmware exacts. Les installateurs refusent les
  autres machines sauf avec `--force`.
- Si vous avez utilisé une ancienne version du correctif batterie, relancez l'installateur
  du correctif 4.

## Sécurité

Les installateurs et désinstallateurs s'exécutent en root : **lisez-les avant de les
lancer**. Rien n'est téléchargé, sauf le fork de msi-ec, à un commit figé (correctif 1).
Les outils de recherche sont différents : la plupart demandent root et ont été écrits
pour une seule machine ; lisez [`recherche/README.fr.md`](recherche/README.fr.md) avant
d'en lancer un.

## Tests

    bash tests/lancer.sh

Lance tous les tests sur une racine temporaire avec de faux outils système ; rien ne
touche `/usr`, `/etc`, `/sys` ni `/var`.

## Projets liés

- [Fork de msi-ec](https://github.com/swald54000/msi-ec) (branche `gs76`) : le pilote
  installé par le correctif 1
- [omarchy-msi-fans](https://github.com/swald54000/omarchy-msi-fans) : le widget du
  correctif 6
- [KLC Light](https://github.com/swald54000/klc-light) : éditeur d'éclairage du clavier
  touche par touche, pour la même machine
- [Recherche](recherche/README.fr.md) : mesures et questions ouvertes

## Licence

MIT, voir [LICENSE](LICENSE).
