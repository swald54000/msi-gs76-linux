# Recherche : MSI GS76 Stealth sous Linux

*English version: [README.md](README.md).*

Ce dossier contient l'enquête qui a mené aux correctifs de `correctifs/` : les outils,
les mesures brutes et ce qu'elles montrent. **Rien ici n'est nécessaire pour utiliser
les correctifs.**

> **Attention : ce sont des outils de recherche, pas des correctifs.**
> La plupart demandent root. Les outils EC chargent `ec_sys` **en lecture seule**
> (`modprobe ec_sys write_support=0`) et s'arrêtent si `ec_sys` est déjà chargé en
> écriture ; ils le déchargent à la fin. Certains modifient des réglages le temps d'une
> mesure (mode des ventilateurs, `shift_mode`, `super_battery`, fréquence de l'écran,
> PSR d'i915, cache batterie, périphériques USB/PCI, services) et les rétablissent à la
> fin, y compris sur Ctrl-C. Deux installent des fichiers système
> (`diagnostics-energie/enable-psr.sh`, `usb-clavier/install.sh`). Ils ont été écrits
> pour une seule machine : lisez un script avant de le lancer. Aucun octet de l'EC n'a
> été écrit directement pendant cette recherche.

## Machine et étiquettes

Machine mesurée : MSI GS76 Stealth 11UH, BIOS `E17M1IMS.119`, firmware EC
`17M1EMS1.113` (chaîne stockée dans l'EC en `0xA0`, compilé le 2022-04-22) —
**vérifié sur la machine**.

Chaque affirmation ci-dessous porte une étiquette :

- **vérifié sur la machine** : mesuré ou lu sur la machine ci-dessus, avec les outils de
  ce dossier ;
- **source communautaire** (nommée) : repris d'un autre projet, non mesuré ici.

Sources communautaires :

- configuration GS76 de YAMDCC : Codeberg `Sparronator9999/YAMDCC`, fichier
  `Configs/MSI-Stealth-GS76-11UG.xml` (même firmware EC) ;
- msi-ec (`github.com/BeardOverflow/msi-ec`) : issues #325 (GS76 11UG) et #848,
  pull requests #143 et #772 ;
- MControlCenter (alternative à MSI Center pour Linux).

## Contenu

| Dossier | Contenu |
|---|---|
| `ec/` | outils de dump de l'EC, décodeur, comparaison sysfs/EC, 12 dumps en lecture seule |
| `super-battery/` | tests de Super Battery et des limites de puissance (prêts, résultats pas encore publiés) |
| `diagnostics-energie/` | diagnostics de consommation au repos (états C, PSR, fréquence) et leurs sorties (`*.txt`) |
| `usb-clavier/` | quirk noyau pour le contrôleur RVB du clavier : **hypothèse non confirmée** |

## 1. Carte des registres de l'EC

Valeurs lues dans `ec/dumps/` avec `ec/decode.py` (**vérifié sur la machine** sauf
mention contraire). Les dumps ont été pris en mode `comfort` avec une limite de charge
de 80 %.

| Adresse | Signification | Observé | Étiquette |
|---|---|---|---|
| `0x68` | température CPU (°C) | 51–59 | vérifié (égale à la température du package) |
| `0x6A`–`0x70` | températures de la courbe CPU | 52 60 65 70 82 88 100 | octets vérifiés ; signification communautaire (YAMDCC, MControlCenter, PR #143, #848) |
| `0x71` | ventilateur CPU, vitesse actuelle (%) | 0, puis 60 en charge | vérifié |
| `0x72`–`0x78` | vitesses de la courbe CPU (%) | 0 45 50 60 65 70 75 | octets vérifiés ; signification communautaire (mêmes sources) |
| `0x7A`–`0x7F` | hystérésis CPU (°C, montée − descente) | 7 3 3 3 3 3 | octets vérifiés ; signification communautaire (YAMDCC) |
| `0x80` | température GPU (°C) | 0 | vérifié (0 tant que le GPU dédié dort en RTD3) |
| `0x82`–`0x88` | températures de la courbe GPU | 55 61 65 71 77 87 100 | octets vérifiés ; signification communautaire |
| `0x89` | ventilateur GPU, vitesse actuelle (%) | 0 | vérifié (GPU endormi) |
| `0x8A`–`0x90` | vitesses de la courbe GPU (%) | 0 50 60 70 75 80 110 | octets vérifiés ; signification communautaire |
| `0x92`–`0x97` | hystérésis GPU (°C) | 8 3 3 3 3 5 | octets vérifiés ; signification communautaire (YAMDCC) |
| `0x98` bit 7 | Cooler Boost | bit à 0 (inactif) | communautaire (msi-ec, MControlCenter) |
| `0xA0`–`0xBB` | version et date de compilation du firmware EC | `17M1EMS1.113`, 2022-04-22 | vérifié |
| `0xBF` | partage d'alimentation USB | `0x28` | valeur vérifiée ; `0x28` = actif, `0x08` = inactif : communautaire (MControlCenter) |
| `0xC8`–`0xC9` | compte-tours du ventilateur CPU : période, gros-boutiste | `0x00A6` à 60 % | vérifié en charge |
| `0xCA`–`0xCB` | compte-tours du ventilateur GPU | 0 | communautaire (PR #772, MControlCenter) ; jamais vu en rotation |
| `0xCC`–`0xCD` | compte-tours du troisième ventilateur (auxiliaire) | 0 | communautaire (issue #325) ; **non vérifié sous charge GPU** |
| `0xD2` | `shift_mode` | `0xC1` | valeur vérifiée ; noms YAMDCC `C0` équilibré (absent de msi-ec), `C1` silencieux/ventilateurs plafonnés à 60 % (= `comfort` de msi-ec), `C2` batterie maximale 10 W, `C4` haute performance : communautaire, pas tous vérifiés |
| `0xD4` | `fan_mode` | auto `0x0D`, silent `0x1D`, advanced `0x8D` | vérifié |
| `0xD7` | limite de charge : `0x80` + pourcentage | `0xD0` (80 %) | vérifié |
| `0xEB` (masque `0x0F`) | Super Battery | `0x0` (inactif) | vérifié (voir § 4) |

Vitesse en tr/min = constante / période : 478000 dans la PR #772, 480000 dans
MControlCenter (**source communautaire**). Mesuré : la période `0xA6` (166) donne
environ 2880 tr/min alors que msi-ec indiquait 60 % (**vérifié sur la machine**,
`ec-dump-load.sh`).

Comportement :

- Passer `fan_mode` d'auto à silent ou advanced ne change que `0xD4` : la table des
  courbes est identique dans les trois modes — **vérifié sur la machine**.
- En mode silent, le ventilateur CPU est resté à 0 % jusqu'à 66 °C — **vérifié sur la
  machine**.
- En mode auto, sous pleine charge CPU, le ventilateur n'a démarré qu'après environ
  35 s, vers 64 °C — **vérifié sur la machine**. L'issue #848 indique que le mode auto
  ignore ou plafonne la courbe et que le mode advanced l'applique — **source
  communautaire**.
- `realtime_fan_speed` (msi-ec) est un pourcentage, pas des tr/min — **vérifié sur la
  machine**.
- Les ventilateurs hwmon `fan1`–`fan4` de `msi_wmi_platform` indiquent toujours 0 tr/min,
  ce qui rend `sensors` trompeur — **vérifié sur la machine**.
- Le troisième ventilateur tourne quand le GPU atteint environ 66 °C ; l'EC impose au
  moins 70 % au ventilateur GPU quand le CPU atteint 76 °C ; MSI Center masque la
  dernière ligne de la courbe — **source communautaire** (issue #325).
- MControlCenter écrit des octets bruts dans l'EC sans les valider, active le mode
  advanced en écrivant `0x8D` dans `0xD4` et le réapplique après la sortie de veille,
  car l'EC réinitialise le mode — **source communautaire** (MControlCenter).
- Lancer `nvidia-smi` réveille le GPU dédié — **vérifié sur la machine**.

### Question ouverte : 6 ou 7 températures par courbe ?

Les sept octets `0x6A`–`0x70` contiennent 52 60 65 70 82 88 100 et `0x82`–`0x88`
contiennent 55 61 65 71 77 87 100 (**vérifié sur la machine**). Deux lectures existent :

- **6 seuils, 7 vitesses** (`s0 t1 s1 … t6 s6` ; le septième octet, 100, n'est pas
  touché) : configuration GS76 de YAMDCC, MControlCenter, PR #143 — **source
  communautaire**. Les six octets d'hystérésis vont dans ce sens : les températures de
  descente qu'ils donnent (45 57 62 67 79 85 pour le CPU) correspondent aux valeurs par
  défaut de YAMDCC.
- **7 paires température/vitesse** : issue #848 (firmware `15K1IMS1`, mêmes adresses) —
  **source communautaire**.

**La question n'est pas tranchée.** Aucune expérience d'écriture n'a été faite.
`decode.py` et le fork de msi-ec (correctif 1) utilisent le modèle à 6 seuils.

## 2. Bugs ACPI du BIOS et effet mesuré

- **État de la batterie `_BST`** : la méthode se termine par `Sleep (0x64)`, donc chaque
  lecture hors cache prend environ 114 ms ; chaque interrogation provoque une saccade
  visible en jeu — **vérifié sur la machine** (`measure-battery.sh`). Sans ce `Sleep`
  (essai avec une surcharge complète de la DSDT, non publiée), une lecture prend environ
  13 ms, la valeur de la section 1 de `diag-root.txt` — **vérifié sur la machine**.
  Contournement publié : cache batterie (correctif 4).
- **Surcharge complète de la DSDT écartée** : elle fige des adresses mémoire du firmware.
  Un jour, le firmware a décalé ses régions ACPI de `0x10000` ; la surcharge pointait
  alors vers des fenêtres PCI périmées et le disque NVMe n'était plus trouvé au
  démarrage — **vérifié sur la machine**. D'où la SSDT en ajout seul (correctif 2), qui
  ne contient aucune adresse.
- **`\_TZ.ETMD` absent** : `\_SB.IETM._OSC` échoue, donc les réglages Intel DTT
  n'arrivent jamais à `thermald` — **vérifié sur la machine**. La SSDT définit `ETMD` ;
  les erreurs `_OSC` ont disparu — **vérifié sur la machine**. Effet de bord : l'espace
  utilisateur démarre environ 0,5 s plus tôt et `thermald` peut démarrer avant
  `intel_rapl` (correctif 3) — **vérifié sur la machine**.
- **Alias PS/2 du pavé tactile I2C** : le pavé tactile apparaît aussi comme souris
  `SynPS/2` ; mettre `PS2M.I2CT = 1` dans la SSDT supprime l'alias — **vérifié sur la
  machine**. La méthode `PS2M._STA` attend aussi 500 ms au démarrage ; impossible de le
  retirer sans modifier la DSDT — **vérifié sur la machine** (lecture de la DSDT).
- **Objets `PEG0`/`PEG2`/`PEG3` en double** (`AE_ALREADY_EXISTS`) : inoffensifs (`PEG0`
  est le disque NVMe, le GPU est `PEG1`) — **vérifié sur la machine**.
- **Aucun ASPM PCIe déclaré dans la FADT**, donc Linux ne gère pas l'ASPM lui-même ; mais
  le BIOS active déjà l'ASPM L1/L1.2 sur la plupart des liens (`diag-root.txt`,
  section 2), donc `pcie_aspm=force` est inutile — **vérifié sur la machine**.
- **Requête EC `0xC1` chaque seconde** sans gestionnaire (15 requêtes en 15 s,
  `diag-root.txt`, section 3) — **vérifié sur la machine**.
- **Méthodes WMI `WQAK`/`WQAL`/`WMAJ`** déclarées mais non implémentées : inoffensives —
  **vérifié sur la machine**.

## 3. Consommation au repos : PSR, 60 contre 360 Hz, états C

Tous les chiffres : puissance du package CPU (RAPL) et temps passé dans chaque état C du
package au repos, d'après les fichiers `*.txt` de `diagnostics-energie/` — **vérifié sur
la machine**.

- À 360 Hz, le package ne descend jamais sous PC2 (environ 90 % du temps en PC2, 0 % dans
  les états plus profonds ; `diag-root.txt`, `diag-psr.txt`).
- Ce n'est pas une limite du BIOS : le MSR `0xE2` autorise jusqu'à PC10 sur chaque CPU
  (verrouillé ; `pkg-limit.txt`).
- Ce ne sont ni les réveils, ni les périphériques USB externes, ni l'Ethernet, ni le
  lecteur de cartes, ni les services : couper chacun laisse le package en PC2
  (`diag-idle2.txt`, `diag-services.txt`, `diag-wakeups.txt`).
- La cause est le moteur d'affichage : écran éteint, la puissance passe de 2,97 W à
  1,84 W et le package atteint PC3 83 % du temps (`diag-display.txt`).
- La dalle prend en charge le PSR1, mais la VBT de MSI le désactive : i915 journalise
  « PSR disabled by flag », même avec `i915.enable_psr=1` (`diag-psr2.txt`).
- PSR1 forcé via debugfs (`i915_edp_psr_debug` = `0x3`) : à 360 Hz le PSR reste coupé
  (« PSR setup time (330 us) too long ») ; à 60 Hz il s'active (`diag-psr.txt`).

| Fréquence | PSR | Puissance du package | État le plus profond atteint |
|---|---|---|---|
| 360 Hz | coupé | 2,92 W | PC2 91 % |
| 360 Hz | forcé | 2,87 W | PC2 91 % |
| 60 Hz | coupé | 1,73 W | PC3 80 % |
| 60 Hz | forcé, actif | 1,45 W | PC3 84 % |

Source : `diag-psr.txt` (20 s par étape). Correctif publié : PSR forcé au démarrage et
60 Hz sur batterie (correctif 5).

Réserves sur les sorties brutes : l'étape à 60 Hz de `diag-idle.txt` n'est pas fiable
(le script utilise `hyprctl keyword monitor`, que Hyprland 0.56 ignore sans rien dire ;
se fier à `diag-psr.txt`) ; dans `diag-display.txt`, les lignes d'état de l'écran sont
vides à cause d'une erreur de guillemets dans le script (`SyntaxError` Python conservée
dans la sortie), les mesures n'en sont pas affectées.

## 4. Super Battery et limites de puissance

- L'EC impose les limites de puissance du CPU via `intel-rapl-mmio:0` ; les limites MSR
  (`intel-rapl:0`, 95/120 W) restent inertes — **vérifié sur la machine**.
- PL1/PL2 fixés par l'EC selon `shift_mode` : `comfort` 45/64 W, `eco` 10/10 W, `turbo`
  70/109 W — **vérifié sur la machine**. YAMDCC décrit `C2` comme un mode batterie
  maximale à 10 W — **source communautaire**.
- Passer en `eco` fait activer `super_battery` (`0xEB`, masque `0x0F`) par l'EC
  lui-même ; quitter `eco` le désactive. Sur le GS76, « Eco » **est** déjà la Super
  Battery de MSI — **vérifié sur la machine**.
- Une fois, en `comfort` avant tout changement (état du démarrage ?), le MMIO indiquait
  90/109 W jusqu'à ce que `comfort` soit réécrit — **vérifié sur la machine**, cause
  inconnue.

`sb-ec.sh` (sur secteur : dump de l'EC et limites MMIO pour 8 combinaisons de
`shift_mode` et `super_battery`) et `sb-batterie.sh` (sur batterie : puissance moyenne
dans 5 états) sont prêts ; leurs résultats ne sont pas encore publiés.

## 5. Quirk USB du clavier : hypothèse non confirmée

Le contrôleur RVB du clavier (SteelSeries KLC, USB `1038:113a`) échoue parfois à
s'énumérer au démarrage : `can't set config #1, error -71`, ou `device not accepting
address, error -71` (éclairage du clavier éteint) — **vérifié sur la machine** :

- erreur -71 sur 1 démarrage sur 6 dans une série ; sur 46 démarrages du journal,
  5 démarrages avec la variante « set config » et 3 avec l'échec total ;
- sur une analyse de 40 démarrages, chaque échec total suivait un redémarrage à chaud
  (3 sur 17 redémarrages, 0 sur 23 démarrages après extinction) ; couper l'alimentation
  du port ne le rétablit pas, une extinction complète si.

Piste : le contrôleur est en USB 2.01 et annonce l'USB2 LPM (extension BOS USB 2.0,
`bmAttributes 0x2`), et Linux active `usb2_hardware_lpm` pour lui — **vérifié sur la
machine**. Hypothèse : la veille L1 pendant l'énumération provoque l'erreur de
protocole. Test : paramètre noyau `usbcore.quirks=1038:113a:k` (`USB_QUIRK_NO_LPM`,
pour ce seul périphérique) ; dans le noyau, `NO_LPM` fait renvoyer 0 à
`usb_device_supports_lpm()` — **vérifié sur la machine** (source du noyau 7.3).

**Non confirmé** : il faut de nombreux redémarrages à chaud sans erreur avant de
conclure. C'est pourquoi ce n'est pas un correctif.

## Lancer les outils

Lancez-les avec `sudo` **depuis votre compte** (pas depuis un shell root) : les scripts
retrouvent votre utilisateur via `SUDO_USER` pour vous rendre propriétaire des sorties
et, pour les tests d'écran, pour joindre votre session Hyprland. Les sorties sont
écrites **dans le dossier courant** :

    mkdir -p ~/mesures-gs76 && cd ~/mesures-gs76
    sudo bash /chemin/vers/recherche/ec/ec-dump.sh

| Outil | Root | Effet | Sortie |
|---|---|---|---|
| `ec/ec-dump.sh` | oui | EC en lecture seule ; passe `fan_mode` en auto/silent/advanced, puis le rétablit | `./dumps/*.bin` |
| `ec/ec-dump-load.sh` | oui | EC en lecture seule ; ventilateur en auto, charge tous les cœurs 60 s, puis rétablit le mode | `./dumps/*-charge-*.bin` |
| `ec/decode.py` | non | décode les dumps : `python3 -I ec/decode.py ec/dumps/*.bin` | écran |
| `ec/verifier-sysfs.sh` | oui (en direct) / non (avec un dump) | compare les attributs du fork msi-ec à un dump de l'EC ; `--surveiller N` relève GPU et troisième ventilateur toutes les 10 s ; `SEUIL_CHARGE` = limite attendue (80) | écran |
| `super-battery/sb-ec.sh` | oui, sur secteur | EC en lecture seule ; change `shift_mode`/`super_battery`, rétablit `comfort` + inactif | `./dumps/`, `./resultats-ec.txt` |
| `super-battery/sb-batterie.sh` | oui, sur batterie | cache batterie à 1 s pendant le test, puis rétabli ; `MESURE` = secondes par état (120) | `./resultats-batterie.txt` |
| `diagnostics-energie/diag-root.sh` | oui | lecture seule (cache batterie brièvement à 0) | `./diag-root.txt` |
| `diagnostics-energie/diag-idle.sh` | oui | écran 360 → 60 → 360 Hz | `./diag-idle.txt` |
| `diagnostics-energie/diag-idle2.sh` | oui | force le PSR, coupe USB externes, Ethernet et lecteur de cartes environ 40 s | `./diag-idle2.txt` |
| `diagnostics-energie/diag-wakeups.sh` | oui | lecture seule | `./diag-wakeups.txt` |
| `diagnostics-energie/diag-services.sh` | oui | arrête puis relance `voxtype` (service utilisateur), `nvidia-powerd`, `thermald` | `./diag-services.txt` |
| `diagnostics-energie/diag-display.sh` | oui | débogage KMS, écran éteint 25 s | `./diag-display.txt` |
| `diagnostics-energie/diag-psr.sh` | oui | force le PSR1, écran 360/60 Hz, rétabli | `./diag-psr.txt` |
| `diagnostics-energie/diag-psr2.sh` | oui | débogage KMS, écran 360 → 60 Hz | `./diag-psr2.txt` |
| `diagnostics-energie/measure-battery.sh` | oui | chronomètre 5 lectures de batterie hors cache | écran |
| `diagnostics-energie/read-pkg-limit.sh` | oui | lit le MSR `0xE2` (charge `msr`) | `./pkg-limit.txt` |
| `diagnostics-energie/enable-psr.sh` | oui | **installe** `i915-psr-force.service` (version de travail du correctif 5) | système |
| `usb-clavier/install.sh` / `uninstall.sh` | oui | **ajoute/retire** le quirk dans `/etc/limine-entry-tool.d/` (Limine seulement) | système |
| `usb-clavier/verifier.sh` | non | quirk actif ? erreurs -71 à ce démarrage ? | écran |

Les tests d'écran supposent la dalle du GS76 (`eDP-2`, 1920x1080 à 360/60 Hz) et une
session Hyprland. `diag-idle2.sh` utilise les adresses PCI du contrôleur Ethernet et du
lecteur de cartes du GS76.

## À propos des sorties publiées

Les fichiers `*.txt` et les dumps ont été relus avant publication. Modifications :
chemins de sortie réduits au nom du fichier ; modèles de la souris et du clavier USB
externes remplacés par une mention générique (`diag-idle2.txt`) ; noms des applications
de l'utilisateur remplacés par `[application utilisateur]` dans `diag-wakeups.txt` ;
adresses PCI raccourcies en `bus:périphérique.fonction` dans `diag-root.txt`. Les dumps
de l'EC ne contiennent aucun numéro de série ; leur seul texte est la version et la date
de compilation du firmware EC. Les mesures elles-mêmes sont inchangées.
