# Rapport : Distribution NixOS pour navigation maritime (style OpenPlotter)

## Contexte

Développement d'une configuration NixOS déclarative pour station de navigation embarquée sur Raspberry Pi, équivalent fonctionnel d'OpenPlotter mais entièrement reproductible et versionnable.

---

## Stack logicielle cible

| Composant | Rôle | Statut nixpkgs |
|---|---|---|
| **pypilot** | Pilote automatique (Python + C extensions) | Absent — à packager |
| **signalk-server** | Hub de données marines (Node.js) | Absent — à packager |
| **opencpn** | Cartographie / chartplotter | Présent |
| **gpsd** | Démon GPS | Présent (`services.gpsd`) |
| **opencpn-plugin-pypilot** | Contrôle route → pypilot depuis opencpn | Absent — à packager |

---

## Hardware supporté

- **Raspberry Pi 4** (cible principale, support NixOS mature via `nix-community/raspberry-pi-nix`)
- **Raspberry Pi 5** (expérimental)
- **Pypilot HAT** : ICM20948 (I2C), LCD JLX12864, RF 433MHz, connexion moteur controller
- **MacArthur HAT** : UART0 (AIS/NMEA), I2C (IMU 9DOF), STEMMA QT, gestion alimentation

Les deux HATs utilisent des interfaces Linux standard (i2c-dev, ttyAMA0, GPIO) configurables déclarativement.

---

## Architecture du flake

```
flake.nix                       # nixosConfigurations + checks.<system> + deploy
├── modules/
│   ├── navigation.nix          # Module principal, options haut niveau
│   ├── pypilot.nix             # Service systemd pypilot
│   ├── signalk.nix             # Service systemd signalk-server
│   ├── opencpn.nix             # Config XML opencpn générée
│   ├── gps-time.nix            # Synchro horloge GPS via chrony (hors ligne)
│   └── hardware/
│       ├── pypilot-hat.nix     # I2C, serial, overlays DT
│       └── macarthur-hat.nix   # UART0, I2C, power management
├── pkgs/
│   ├── pypilot.nix             # buildPythonPackage (+ checkPhase)
│   ├── rtimulib2.nix           # Dépendance C++ de pypilot, absente de nixpkgs
│   ├── signalk-server.nix      # buildNpmPackage
│   ├── opencpn-plugin-pypilot.nix
│   └── avnav.nix               # (futur) chartplotter web
├── tests/
│   ├── integration.nix         # runNixOSTest aarch64 (CI, jetable)
│   ├── hardware-checks.sh      # Validation banc réel via SSH (niveau 3)
│   └── fixtures/
│       └── sample.nmea         # Flux NMEA simulé pour gpsfake
└── hosts/
    ├── common.nix              # Config partagée par tous les hôtes
    ├── navpi/                  # Production : RPi à bord
    │   └── configuration.nix
    ├── banc-rpi4/              # Banc matériel RPi 4
    │   └── configuration.nix
    ├── banc-rpi5/              # Banc matériel RPi 5
    │   └── configuration.nix
    └── lab-vm/                 # Lab VM aarch64 persistant (niveau 2 mode B)
        └── configuration.nix
```

Tous les hôtes sont déclarés comme `nixosConfigurations` distincts dans le flake et partagent les mêmes modules `navigation` / hardware. Cela permet d'ajouter facilement d'autres bateaux ou bancs sans dupliquer la logique :

```nix
# flake.nix (extrait)
nixosConfigurations = {
  navpi      = mkHost { system = "aarch64-linux"; hw = "macarthur-hat"; modules = [ ./hosts/navpi ]; };
  banc-rpi4  = mkHost { system = "aarch64-linux"; hw = "pypilot-hat";   modules = [ ./hosts/banc-rpi4 ]; };
  banc-rpi5  = mkHost { system = "aarch64-linux"; hw = "macarthur-hat"; modules = [ ./hosts/banc-rpi5 ]; };
  lab-vm     = mkHost { system = "aarch64-linux"; hw = null;            modules = [ ./hosts/lab-vm ]; };
};
```

---

## Interface utilisateur (options NixOS)

L'objectif est une configuration minimale fonctionnelle out-of-the-box :

```nix
services.navigation = {
  enable = true;

  hardware = "macarthur-hat"; # ou "pypilot-hat" — configure I2C/UART automatiquement

  gps = {
    enable = true;
    device = "/dev/gps0"; # symlink udev auto-généré selon vendorId/productId
  };

  pypilot = {
    enable = true;
    imu = "icm20948"; # ou "mpu9250", "mpu9255"
  };

  signalk.enable = true;

  opencpn = {
    enable = true;
    plugins = [ "pypilot" ]; # plugin pypilot_pi pré-installé
  };
};
```

Cette configuration unique câble automatiquement toute la plomberie décrite ci-dessous.

---

## Plomberie réseau déclarative

### Flux de données complet

```
[GPS hardware]
      │ /dev/gps0 (udev symlink)
      ▼
   [gpsd :2947]
      │ gpsd protocol
      ▼
[signalk-server :3000]  ◄────── [pypilot :20220] (NMEA TCP + zeroconf autodiscovery)
      │                                 ▲
      │ NMEA TCP :10110                 │ route instructions
      ▼                                 │
   [opencpn] ──── plugin pypilot ───────┘
                  TCP :23322
```

### 1. Règles udev (Serial → Devices)

```nix
services.udev.extraRules = ''
  SUBSYSTEM=="tty", ATTRS{idVendor}=="XXXX", ATTRS{idProduct}=="YYYY",
    SYMLINK+="gps0", TAG+="systemd"
  SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0042",
    SYMLINK+="pypilot_motor", TAG+="systemd"
'';
```

Les `idVendor`/`idProduct` sont des options du module, avec valeurs par défaut pour le matériel courant.

### 2. gpsd → signalk

```nix
services.gpsd = {
  enable = true;
  devices = [ config.services.navigation.gps.device ];
};
# signalk se connecte à gpsd via provider natif
```

### 3. pypilot ↔ signalk

pypilot détecte signalk via **zeroconf/mDNS** automatiquement si les deux tournent sur le même host. La seule config nécessaire est l'autorisation dans `settings.json` de signalk, générée par Nix :

```nix
# Injecté dans ~/.signalk/settings.json via activation script
signalk.settings.pipedProviders = [{
  id = "pypilot";
  pipeElements = [{
    type = "providers/tcp";
    options = { host = "localhost"; port = 20220; };
  }];
}];
```

### 4. opencpn ↔ signalk (lecture NMEA)

opencpn se connecte au port NMEA TCP `:10110` exposé par signalk. Généré dans `~/.opencpn/opencpn.conf` :

```ini
[Settings/NMEADataSource]
DataConnections=0;2;localhost;10110;0;0;...
```

### 5. opencpn → pypilot (envoi de route)

Via le plugin `pypilot_pi` (TCP `:23322`). Autoconfiguration si pypilot est en localhost.

---

## Points de difficulté & solutions

### pypilot : RTIMULib2

RTIMULib2 est une bibliothèque C++ absente de nixpkgs. Il faut la packager :

```nix
# pkgs/rtimulib2.nix
{ stdenv, fetchFromGitHub, cmake }:
stdenv.mkDerivation {
  pname = "rtimulib2";
  version = "unstable";
  src = fetchFromGitHub {
    owner = "seandepagnier";
    repo = "RTIMULib2";
    rev = "...";
    hash = "sha256-...";
  };
  nativeBuildInputs = [ cmake ];
}
```

pypilot a également des extensions C compilées avec SWIG (`linebuffer`, `arduino_servo`) — géré normalement via `buildPythonPackage` avec `nativeBuildInputs = [ swig ]`.

Le `setup.py` de pypilot vérifie la présence d'`apt` — nécessite un patch trivial.

### signalk : plugins dynamiques

signalk installe ses plugins via `npm` dans `~/.signalk/node_modules/` au runtime, ce qui est incompatible avec le store Nix en lecture seule.

**Solution retenue** : `StateDirectory` systemd pour `~/.signalk/`, avec les plugins voulus pré-installés dans le package via `buildNpmPackage` et copiés à l'activation. Les plugins additionnels peuvent toujours être installés manuellement via l'interface web.

```nix
systemd.services.signalk = {
  serviceConfig.StateDirectory = "signalk";
  # Script d'activation copie les plugins Nix dans StateDirectory
};
```

### opencpn : configuration XML/INI

opencpn utilise un fichier `~/.opencpn/opencpn.conf` modifié au runtime. Solution : générer un fichier de config initial via `writeText`, déployé par un activation script uniquement si absent (première installation).

### Données de calibration pypilot

Les données de calibration IMU sont écrites au runtime. Elles vivent dans `StateDirectory` de systemd, hors du store Nix, ce qui est correct.

---

## Plan d'implémentation suggéré

### Phase 1 — Packages (prioritaire)

1. `pkgs/rtimulib2.nix` — lib C++ sans dépendances complexes
2. `pkgs/pypilot.nix` — buildPythonPackage avec patch setup.py
3. `pkgs/signalk-server.nix` — buildNpmPackage (node2nix ou fetchNpmDeps)

### Phase 2 — Modules hardware

4. `modules/hardware/pypilot-hat.nix` — I2C enable, kernel modules, device tree overlays
5. `modules/hardware/macarthur-hat.nix` — UART0, I2C, power management udev

### Phase 3 — Services

6. `modules/pypilot.nix` — systemd service + StateDirectory
7. `modules/signalk.nix` — systemd service + gestion plugins + settings.json
8. `modules/opencpn.nix` — config initiale + plugin pypilot

### Phase 4 — Intégration & hôtes

9. `modules/navigation.nix` — module principal qui orchestre tout
10. `modules/gps-time.nix` — synchro horloge GPS via chrony (hors ligne)
11. `hosts/common.nix` + déclaration des `nixosConfigurations` (navpi, banc-rpi4, banc-rpi5, lab-vm)
12. Génération des SD images par hôte + procédure de bootstrap/flash documentée

### Phase 5 — Tests, déploiement & CI

13. `passthru.tests` / `checkPhase` sur chaque package (niveau 1)
14. `tests/integration.nix` — test d'intégration VM aarch64 avec GPS simulé (niveau 2A)
15. `hosts/lab-vm/` — lab VM aarch64 persistant + workflow `nixos-rebuild --target-host` (niveau 2B)
16. Pipeline CI (`nix flake check` avec binfmt aarch64, idéalement runner natif ARM)
17. Configuration deploy-rs (banc-rpi4, banc-rpi5) + `tests/hardware-checks.sh` (niveau 3)

### Phase 6 — Logiciels complémentaires (futur)

18. `pkgs/avnav.nix` — chartplotter web
19. Intégration xygrib (déjà packagé) dans la suite par défaut

---

---

## Stratégie de tests

> **Priorité : validation sur matériel réel.** Le niveau 3 (banc RPi physique) est la voie de validation privilégiée, car seul le matériel réel exerce le HAT, le bus I2C, l'IMU, le motor controller et l'UART. Le niveau 2 (VM aarch64 émulée) est **optionnel** : utile pour un retour rapide en CI sans matériel, mais l'émulation ne reproduit pas le hardware et reste lente. En cas d'arbitrage, privilégier toujours le banc réel.

Trois niveaux complémentaires, du plus rapide/isolé au plus réaliste.

### Niveau 1 — Tests unitaires des packages

Chaque package custom expose ses tests via l'attribut `passthru.tests` ou `checkPhase` :

- **pypilot** : exécuter la suite Python du projet dans `checkPhase` (pytest si disponible), plus un smoke test que les extensions SWIG (`linebuffer`, `arduino_servo`) se chargent : `python -c "import pypilot.linebuffer"`.
- **rtimulib2** : vérifier que la lib se compile et que les bindings Python s'importent.
- **signalk-server** : exécuter `npm test` du projet en sandbox (réseau désactivé — attention aux tests nécessitant un accès réseau, à patcher ou skip).

```nix
# pkgs/pypilot.nix (extrait)
buildPythonPackage rec {
  # ...
  nativeCheckInputs = [ pytest ];
  checkPhase = ''
    python -c "import pypilot.linebuffer; import pypilot.arduino_servo.arduino_servo"
    pytest tests/ || true  # selon couverture réelle du projet amont
  '';
}
```

Ces tests tournent à chaque `nix build` et bloquent l'intégration d'un package cassé. Les exposer dans `checks.<system>` du flake pour `nix flake check`.

### Niveau 2 (optionnel) — Lab de test aarch64 (émulé)

La cible étant toujours un RPi (aarch64), les tests d'intégration tournent en **aarch64 émulé**, pas en x86_64 — l'objectif est précisément de confirmer la compatibilité aarch64 de toute la stack.

**Activation de l'émulation** sur le runner/poste de dev (hôte x86_64) :

```nix
# configuration du runner
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

Ceci enregistre QEMU comme interpréteur binfmt pour aarch64. Nix peut alors construire et exécuter des dérivations aarch64 de façon transparente.

> **Contraintes à connaître** :
> - L'émulation QEMU/TCG (pas de KVM possible entre architectures différentes) est **lente**. Tant qu'on ne recompile pas (on tire les binaires aarch64 depuis le cache Hydra + cachix `nix-community`), ça reste utilisable. Éviter à tout prix de recompiler le kernel en émulation.
> - L'activation de `emulatedSystems` peut nécessiter une compilation de QEMU (coût ponctuel).
> - **Émulation ≠ RPi réel** : la VM aarch64 n'a ni HAT, ni bus I2C physique, ni device tree du Pi. Le niveau 2 valide que **les binaires aarch64 tournent et que les services démarrent en aarch64** ; tout ce qui touche au hardware réel relève du niveau 3.

#### Deux modes d'usage du lab

**A. Tests jetables pour la CI** — `pkgs.testers.runNixOSTest` avec nœuds aarch64, démarrés/détruits à chaque run. Idéal pour `nix flake check`.

```nix
# tests/integration.nix
pkgs.testers.runNixOSTest {
  name = "navigation-integration-aarch64";
  node.pkgs = pkgs;  # pkgs aarch64-linux
  nodes.boat = { ... }: {
    imports = [ self.nixosModules.navigation ];
    services.navigation = { enable = true; pypilot.enable = true; signalk.enable = true; };
  };
  testScript = ''
    boat.start()
    boat.wait_for_unit("signalk.service")
    boat.wait_for_unit("pypilot.service")
    boat.wait_for_open_port(20220)   # pypilot NMEA
    boat.wait_for_open_port(3000)    # signalk API
    boat.succeed("curl -f http://localhost:3000/signalk")
    # GPS simulé via gpsfake
    boat.succeed("gpsfake -c 0.1 ${./fixtures/sample.nmea} &")
    boat.wait_until_succeeds(
      "curl -s http://localhost:3000/signalk/v1/api/vessels/self/navigation/position | grep -q latitude"
    )
  '';
}
```

**B. Lab VM persistant pour l'itération manuelle** — Plutôt qu'une VM qui démarre/s'éteint à chaque test, on déclare une VM aarch64 **comme un hôte à part entière** (`nixosConfigurations.lab-vm`) qu'on lance une fois et qu'on laisse tourner. On la met ensuite à jour comme n'importe quelle machine distante :

```bash
# Démarrage initial (une seule fois) — VM aarch64 persistante avec disque
nix run .#lab-vm   # ou un wrapper run-*-vm avec disque persistant

# Itérations suivantes : on POUSSE la mise à jour dans la VM déjà allumée
nixos-rebuild switch --flake .#lab-vm \
  --target-host root@lab-vm.local --build-host localhost
```

Les tests deviennent alors des scripts lancés via SSH contre cette VM vivante, ce qui **unifie le workflow avec le banc matériel** (même commande `nixos-rebuild --target-host`). C'est nettement plus rapide à itérer que de reconstruire une VM jetable.

> Recommandation : **mode A** (jetable) pour la CI automatisée, **mode B** (persistant) pour le développement au quotidien. Les deux partagent les mêmes modules `navigation`.

### Niveau 3 — Banc de test matériel réel

Un RPi physique dédié, accessible sur le réseau, sur lequel on déploie la config réelle aarch64 avec le vrai HAT.

**Tests sur le banc** (ce qui ne peut PAS être simulé) :

- Détection réelle de l'IMU sur le bus I2C : `i2cdetect -y 1` doit montrer l'adresse `0x68` (MPU) ou celle de l'ICM20948
- pypilot lit effectivement les gyros : `pypilot_boatimu` retourne des données cohérentes
- Le motor controller est détecté : `pypilot_servo` détecte le contrôleur
- Lecture UART du HAT MacArthur (AIS/NMEA)
- Comportement de l'alimentation / shutdown propre du HAT
- Synchro horloge GPS après boot sans réseau (voir section dédiée)

Idéalement, un script de validation post-déploiement (lançable via SSH) automatise ces vérifications hardware et produit un rapport pass/fail.

---

## Installation & déploiement sur RPi

### Le problème de nixos-anywhere sur Raspberry Pi

`nixos-anywhere` est la solution idéale en théorie, **mais elle ne fonctionne pas directement sur RPi** : le kernel Raspberry Pi ne supporte pas `kexec` (absence de `/proc/kcore`), ce qui fait échouer l'étape de bascule vers l'installeur. Contourner cela demande de booter au préalable un installeur NixOS (depuis USB), ce qui annule l'avantage du "one-shot par SSH".

### Procédure recommandée (deux temps)

**Étape 1 — Bootstrap initial via SD image** (une seule fois par machine)

Le flake génère une image SD bootable par hôte, via `nvmd/nixos-raspberrypi` ou `raspberry-pi-nix`. L'image embarque déjà la config (utilisateur, SSH activé, clés) :

```bash
# Construire l'image SD pour le banc RPi4 (depuis un host avec binfmt aarch64,
# ou directement sur un Pi, ou via cache binaire)
nix build .#nixosConfigurations.banc-rpi4.config.system.build.sdImage

# Flasher sur la carte SD
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

> Astuce : construire l'image en émulation aarch64 sature le CPU (surtout le kernel). Préférer le cache binaire (`nix-community.cachix.org`) ou, pour le tout premier build, compiler directement sur un Pi via `nix build --store ssh-ng://...`.

**Étape 2 — Itérations déclaratives par SSH** (à chaque mise à jour ensuite)

Une fois le Pi démarré et joignable, tout passe en déclaratif pur, sans jamais re-flasher :

```bash
# Build local (avec binfmt) + push de la closure + activation distante
nixos-rebuild switch \
  --flake .#banc-rpi4 \
  --target-host root@banc-rpi4.local \
  --build-host localhost
```

La gestion de la partition firmware (`/boot/firmware`, `config.txt`, overlays DT) est intégrée aux activation scripts du module RPi, donc les bascules de génération se font sans intervention manuelle.

### Déploiement robuste avec rollback : deploy-rs

Pour un banc distant qu'on ne veut pas risquer de rendre injoignable, **deploy-rs** ajoute un rollback automatique si le healthcheck post-activation échoue :

```nix
deploy.nodes.banc-rpi4 = {
  hostname = "banc-rpi4.local";
  profiles.system = {
    sshUser = "root";
    path = deploy-rs.lib.aarch64-linux.activate.nixos
             self.nixosConfigurations.banc-rpi4;
  };
};
```

```bash
deploy .#banc-rpi4   # rollback auto si la machine ne confirme pas l'activation
```

Pour le **lab VM persistant** (niveau 2, mode B), c'est exactement la même mécanique : la VM est un hôte déclaré dans le flake, mis à jour via `nixos-rebuild --target-host` ou deploy-rs.

### Pipeline CI suggéré

```
┌─────────────────────────────────────────────────────────────┐
│ git push                                                    │
│   ├─ nix flake check  (runner avec binfmt aarch64)          │
│   │    ├─ Niveau 1 : tests unitaires des packages (aarch64) │
│   │    └─ Niveau 2A (optionnel) : intégration VM aarch64    │
│   └─ déploiement banc → VALIDATION PRINCIPALE               │
│        deploy .#banc-rpi4 / .#banc-rpi5                     │
│        └─ Niveau 3 : hardware-checks.sh via SSH             │
└─────────────────────────────────────────────────────────────┘

Lab VM persistant (niveau 2B, optionnel) : hors CI, itération rapide
   nixos-rebuild switch --flake .#lab-vm --target-host root@lab-vm.local
```

Le niveau 1 tourne sur chaque push. Le niveau 2 (VM émulée) est optionnel et peut être activé pour un feedback sans matériel, mais **la validation de référence est le niveau 3 sur banc réel**, déclenché sur tag de release ou manuellement.

> Note CI : un runner GitHub/GitLab x86_64 avec `binfmt` aarch64 fonctionne mais reste lent en émulation. Pour accélérer, envisager un **runner natif aarch64** (ex. instance ARM cloud, ou un des RPi/SBC dédié au build) qui exécute les tests sans émulation.

---

## Évolutions futures

### Suite logicielle de navigation embarquée

| Logiciel | Rôle | Statut nixpkgs |
|---|---|---|
| **opencpn** | Chartplotter principal | Présent |
| **xygrib** | Visualisation/téléchargement GRIB météo (successeur de zygrib) | Présent |
| **zygrib** | Ancien viewer GRIB (déprécié, remplacé par xygrib) | À éviter — utiliser xygrib |
| **avnav** | Chartplotter web (Andreas Vogel), bon support tactile | Absent — à packager |
| **qtVlm** | Navigation + routage météo | Absent + **freeware non-libre** (packaging délicat, redistribution à vérifier) |
| **gpsd / gpsd-clients** | Outils GPS (xgps, cgps, gpsmon) | Présent |
| **pps-tools** | Diagnostic PPS pour synchro horloge | Présent |

Recommandation : démarrer avec opencpn + xygrib (déjà packagés), ajouter avnav dans un second temps (packaging web app, modèle similaire à signalk). qtVlm en dernier vu sa licence.

### Synchronisation horloge via GPS (sans Internet)

Indispensable à bord : sans connexion Internet, l'horloge système doit se caler sur le temps GPS. Solution standard `gpsd` + `chrony`.

Deux niveaux de précision :

1. **SHM via gpsd (USB GPS, simple)** — précision milliseconde, suffisante pour les logs et l'horodatage. chrony lit le temps que gpsd extrait des trames NMEA.

2. **PPS (Pulse-Per-Second, précision microseconde)** — si le GPS expose un signal PPS sur une broche GPIO/DCD. Nettement plus précis mais nécessite câblage matériel et configuration du module noyau `pps_gpio`.

```nix
# modules/gps-time.nix
{ config, lib, pkgs, ... }: {
  # gpsd alimente chrony via mémoire partagée (SHM)
  services.gpsd = {
    enable = true;
    devices = [ config.services.navigation.gps.device ];
    extraArgs = [ "-n" ];  # lecture immédiate au démarrage
  };

  services.chrony = {
    enable = true;
    # Pas de serveurs NTP requis hors ligne ; le GPS est la référence
    extraConfig = ''
      # Référence temps issue des trames NMEA via gpsd (SHM 0)
      refclock SHM 0 offset 0.5 delay 0.2 refid GPS

      # Si PPS disponible (précision µs) — décommenter après câblage GPIO :
      # refclock PPS /dev/pps0 lock NMEA refid PPS prefer

      # Autorise un grand saut au boot (horloge potentiellement très fausse)
      makestep 1.0 3
      # Synchronise aussi l'horloge matérielle (RTC) si présente
      rtcsync
    '';
  };

  # Pour PPS uniquement : charger le bon module noyau
  # boot.kernelModules = [ "pps_gpio" ];
}
```

> **Point d'attention connu** : sur RPi, l'ordre de démarrage gpsd/chrony et les paramètres baud du GPS demandent souvent un réglage fin. Plusieurs retours signalent qu'il faut fixer explicitement les options gpsd (baud, format) et parfois ajouter un délai avant le démarrage de chrony pour laisser le GPS acquérir un fix. À valider sur le banc matériel (niveau 3) — c'est précisément le type de comportement non simulable en VM.

Cette fonctionnalité devra avoir son propre test sur le banc : vérifier qu'après un boot sans réseau, `chronyc sources` montre bien le GPS comme source sélectionnée (`*`) et que l'horloge se cale.

---

## Références

- pypilot : https://github.com/pypilot/pypilot
- pypilot dépendances : https://github.com/pypilot/pypilot/blob/master/dependencies.py
- RTIMULib2 : https://github.com/seandepagnier/RTIMULib2
- signalk-server : https://github.com/SignalK/signalk-server
- nix-community/raspberry-pi-nix : https://github.com/nix-community/raspberry-pi-nix
- MacArthur HAT : https://macarthur-hat-documentation.readthedocs.io/
- OpenPlotter (référence fonctionnelle) : https://github.com/openplotter/openplotter-settings
- NixOS Test Driver (doc officielle) : https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html
- Écriture de tests NixOS (manuel nixpkgs) : https://github.com/NixOS/nixpkgs/blob/master/nixos/doc/manual/development/writing-nixos-tests.section.md
- deploy-rs (déploiement avec rollback) : https://github.com/serokell/deploy-rs
- nixos-anywhere (limites kexec sur RPi) : https://github.com/nix-community/nixos-anywhere/issues/183
- nvmd/nixos-raspberrypi (images SD + déploiement déclaratif) : https://github.com/nvmd/nixos-raspberrypi
- Émulation aarch64 via binfmt : https://wiki.nixos.org/wiki/QEMU
- Cross-platform compilation (NixOS & Flakes Book) : https://nixos-and-flakes.thiscute.world/development/cross-platform-compilation
- GPSD Time Service HOWTO : https://gpsd.gitlab.io/gpsd/gpsd-time-service-howto.html
- chrony FAQ (refclock GPS/PPS) : https://chrony-project.org/faq.html
- avnav : https://www.wellenvogel.net/software/avnav/docs/beschreibung.html
- xygrib : https://opengribs.org/
