# Correctif 6 : widget ventilateurs

Le widget (plugin Omarchy) affiche l'état des ventilateurs et permet de changer
leur mode depuis la barre. Il vit dans un dépôt séparé ; ce dossier ne contient
que cette notice et un vérificateur.

## Prérequis

Le **correctif 1** (pilote msi-ec) doit être installé : le widget écrit dans
`fan_mode`, réservé au groupe `msi-ec`. Après l'installation du correctif 1,
fermez la session puis rouvrez-la pour que l'appartenance au groupe soit prise
en compte.

## Installation

```
omarchy plugin add https://github.com/swald54000/omarchy-msi-fans.git --enable
```

## Vérification

```
./verifier.sh
```

Codes de sortie : 0 sain, 1 non installé, 2 défaut (le détail est affiché).

## Désinstallation

```
omarchy plugin remove swald.fans
```
