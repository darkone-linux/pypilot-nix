# pypilot-nix

[![CI](https://img.shields.io/github/actions/workflow/status/darkone-linux/pypilot-nix/ci.yml?branch=main&label=CI&logo=github)](https://github.com/darkone-linux/pypilot-nix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-26.11+-blue.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![Platform](https://img.shields.io/badge/platform-aarch64--linux-lightgrey)](.)
[![Built with Nix](https://img.shields.io/badge/Built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)

[English](README.md) | **Français**

**pypilot-nix** est une distribution NixOS déclarative pour la navigation
maritime embarquée sur Raspberry Pi — l'équivalent reproductible et versionné
d'OpenPlotter.

Toute la pile pilote automatique / hub de données / traceur de cartes démarre
depuis une seule option NixOS, se construit en une image SD bootable par bateau,
et se met à jour par SSH comme n'importe quelle machine NixOS. Elle cible le
Raspberry Pi 4 (principal) et le Pi 5 (expérimental) sur `aarch64-linux`, avec le
**Pypilot HAT** ou le **MacArthur HAT**.

## Fonctionnalités

- **Point d'entrée unique** : `services.navigation.enable = true` câble toute la pile.
- **pypilot** : démon pilote automatique avec fusion IMU RTIMULib et contrôle moteur.
- **Signal K** : hub de données maritimes sur le port 3000, NMEA0183 sur TCP 10110.
- **OpenCPN** : traceur de cartes avec config générée et emplacement pour le plugin pypilot.
- **Horloge GPS hors-ligne** : `gpsd` et `chrony` règlent l'heure sans Internet.
- **HAT matériels** : bus I2C, UART et SPI, modules noyau et overlays device-tree.
- **Périphériques stables** : symlinks udev `/dev/gps0` et `/dev/pypilot_motor` depuis les IDs USB.
- **Découverte de périphériques** : `nav-discover` liste le matériel série et produit du Nix prêt à coller ; un registre `serialDevices` câble udev + Signal K.
- **Images SD par hôte** : une image nommée `pypilot-nix-<host>.img.zst` par machine.
- **Testé en CI** : vérifications d'import des paquets plus un test d'intégration en VM NixOS.
- **Headless** : SSH, mDNS `.local`, un compte admin `skipper`, aucun écran requis.

## Configuration

`hosts/common.nix` démarre la pile (`services.navigation.enable`) avec les
services headless activés par défaut. Un fichier par hôte ne fixe ensuite que le
nom de la machine et le HAT :

```nix
# hosts/navpi/configuration.nix
{ ... }:
{
  imports = [ ../rpi.nix ];

  networking.hostName = "navpi";

  # HAT installé sur le Pi — au choix :
  services.navigation.hardware = "pypilot-hat";
  # services.navigation.hardware = "macarthur-hat";

  # Accéder à Signal K depuis le réseau du bateau :
  services.navigation.signalk.openFirewall = true;

  # Noms /dev stables depuis les IDs `lsusb` :
  # services.navigation.gps.vendorId = "1546";
  # services.navigation.gps.productId = "01a7";
}
```

Hôtes fournis dans le flake :

| Hôte       | Cible            | HAT           | Rôle           |
| ---------- | ---------------- | ------------- | -------------- |
| `navpi`    | Raspberry Pi 4   | Pypilot HAT   | Production     |
| `lab-rpi4` | Raspberry Pi 4   | Pypilot HAT   | Labo / banc    |
| `lab-rpi5` | Raspberry Pi 5 ¹ | MacArthur HAT | Labo / banc    |
| `lab-vm`   | VM aarch64       | aucun         | Labo émulé     |

¹ Le support de boot du Pi 5 est expérimental (image aarch64 générique).

Ajoutez un bateau ou un banc en déclarant une entrée `nixosConfigurations` de
plus dans `flake.nix` et en déposant un `hosts/<host>/configuration.nix` ; les
modules sont partagés, aucune logique n'est dupliquée. L'ensemble des options
vit dans `modules/navigation.nix`.

## Périphériques série & découverte

Le matériel maritime (AIS, GPS, sondes profondeur/vent, contrôleur moteur du
pilote automatique) se branche en port série USB ou soudé. pypilot-nix les câble
de façon déclarative via un registre unique, et fournit un CLI de découverte pour
le remplir — l'équivalent reproductible de l'app « Serial » d'OpenPlotter.

### Le registre `serialDevices`

Une seule option fait foi pour le symlink udev **et** le provider Signal K. Le
nom de l'attribut est le symlink `/dev` :

```nix
services.navigation.serialDevices.ttyOP_ais = {
  match = { vendorId = "27c5"; productId = "0402"; serial = "793379380P51"; };
  role = "ais"; # ais | nmea0183 | pilot
  baudrate = 38400;
};
```

- **`match`** épingle le périphérique, comme le *remember* d'OpenPlotter : par
  `vendorId` + `productId` USB (avec `serial` optionnel pour distinguer des
  adaptateurs identiques), ou par `port` (un chemin device-tree tel que
  `fe201000.serial:0.0`) pour un UART soudé sans ID USB.
- **`role`** détermine le câblage :

  | role       | symlink udev | service | provider Signal K       |
  | ---------- | ------------ | ------- | ----------------------- |
  | `ais`      | oui          | signalk | NMEA0183 série @ baud   |
  | `nmea0183` | oui          | signalk | NMEA0183 série @ baud   |
  | `pilot`    | oui          | pypilot | aucun (géré par pypilot) |

Le **GPS** garde son option dédiée, `services.navigation.gps` (gpsd possède le
récepteur et discipline l'horloge). Le NMEA2000/CAN est géré par le module du
HAT MacArthur, pas par ce registre. Les options historiques `ais`/`motor`
fonctionnent toujours — elles sont traduites en interne vers des entrées du
registre.

### Découvrir les périphériques avec `nav-discover`

`nav-discover` est un CLI en lecture seule (installé sur chaque hôte) qui énumère
les ports série et imprime, pour chacun, un extrait Nix prêt à coller :

```shell
nav-discover         # liste les périphériques, devine le rôle par l'ID USB
nav-discover --sniff # ouvre chaque port, lit le NMEA0183 et détecte le rôle
```

Boucle : brancher le matériel, lancer `nav-discover [--sniff]`, coller l'extrait
dans `hosts/<host>/configuration.nix`, puis `nixos-rebuild switch`. Un GPS
détecté produit un extrait `services.navigation.gps` ; l'AIS et les sondes
produisent des entrées `serialDevices`.

`--sniff` n'ouvre pas un port déjà tenu par gpsd ou Signal K : lancez donc le
scan avant d'assigner le périphérique (ou arrêtez d'abord le service qui le
consomme). Sur un hôte avec le bureau labwc, le même scan est accessible depuis
le menu clic-droit sous **Outils → Scan Matériel**.

## Construire l'image SD

Les images SD sont en `aarch64` : construisez-les sur une machine ARM native, un
builder distant, ou un hôte x86_64 avec l'émulation `binfmt`. Le cache
`nix-community` évite de recompiler le gros du système.

```shell
just sd-image navpi
# ou : nix build .#packages.aarch64-linux.navpi-sdImage -o result-navpi
```

Le résultat est une image compressée :

```
result-navpi/sd-image/pypilot-nix-navpi.img.zst
```

Hôtes avec image SD : `navpi`, `lab-rpi4`, `lab-rpi5`. Le `lab-vm` tourne en VM
(voir plus bas).

## Installation

### 1. Flasher la carte SD

L'image est compressée en zstd ; décompressez et écrivez en un seul pipe
(revérifiez la cible — le mauvais périphérique efface un disque) :

```shell
zstd -dc result-navpi/sd-image/*.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### 2. Premier démarrage

L'image embarque SSH et mDNS activés, joignable à `<host>.local` :

- utilisateur `skipper`, mot de passe `NixPypilot` (défaut d'amorçage — à changer)
- pour des déploiements sans mot de passe, ajoutez votre clé à
  `users.users.skipper.openssh.authorizedKeys.keys` et reconstruisez

### 3. Itérer par SSH

Plus de reflashage ensuite : construisez en local et poussez la closure.

```shell
nixos-rebuild switch \
  --flake .#navpi \
  --target-host skipper@navpi.local --use-remote-sudo \
  --build-host localhost
```

Pour un rollback automatique en cas d'échec, ajoutez l'input `deploy-rs` et
utilisez `deploy .#<host>` (pas encore câblé ici).

### VM de labo (sans matériel)

Lancez la VM de labo aarch64 persistante (sur un hôte aarch64, ou x86_64 avec
émulation système complète binfmt), puis mettez-la à jour comme un vrai Pi :

```shell
nix run .#lab-vm
nixos-rebuild switch --flake .#lab-vm --target-host skipper@lab-vm.local --use-remote-sudo
```

## Commandes Just

Le `Justfile` regroupe les commandes du quotidien. Lancez `just` (ou
`just --list`) pour toutes les voir.

| Recette                   | Rôle                                                   |
| ------------------------- | ------------------------------------------------------ |
| `just clean`              | `fix` + `check` + `format` (avant chaque commit)       |
| `just sd-image <host>`    | Construit l'image SD d'un hôte                         |
| `just apply <host> [act]` | Déploie un hôte par SSH (`act` vaut `switch` par défaut) |
| `just update`             | Met à jour les inputs, commit `flake.lock` s'il change |
| `just gc <host>`          | Libère de l'espace sur un hôte puis régénère son boot  |

```shell
just apply lab-rpi4          # nixos-rebuild switch sur lab-rpi4
just apply lab-rpi4 boot     # prépare pour le prochain boot au lieu de switcher
just update                  # bump des inputs, commit auto du lockfile
just gc lab-rpi4             # nix-collect-garbage -d par SSH, rafraîchit le boot
```

Les recettes de déploiement ciblent `skipper@<host>` par SSH et utilisent le
`sudo` de l'hôte : la clé `skipper` doit être autorisée et le compte sudoer.

## Documentation

Voir [`doc/pypilot-nix-specs.md`](doc/pypilot-nix-specs.md) pour la conception
complète, la plomberie du flux de données et la stratégie de test.
