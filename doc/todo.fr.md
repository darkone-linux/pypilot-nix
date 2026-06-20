# TODO — suite au banc lab-rpi4 + investigations

Style télégraphique. `[x]` fait · `[~]` partiel · `[ ]` à faire.

## Déploiement / accès (RÉSOLU)

- [x] Déploiement par clé : `authorizedKeys` (skipper + root) = clé `gponcon@gmail.com`.
- [x] `trusted-users = root @wheel` → push de closure non signée OK (corrige « lacks a signature by a trusted key »).
- [x] `security.sudo.wheelNeedsPassword = false` → `--use-remote-sudo` non interactif.
- [x] Workflow validé : `nixos-rebuild switch/test --flake .#lab-rpi4 --target-host skipper@lab-rpi4 --use-remote-sudo --build-host localhost`.
- Note : bootstrap initial fait via `root@` (clé semée à la main une fois).

## Retours banc — « à faire »

- [x] Clavier azerty (fr) dans `common` (console + session Wayland labwc).
- [x] Ne pas démarrer OpenCPN automatiquement (`desktop.autostartOpencpn = false`).
- [x] Logs `journalctl` investigués (gpiod, renice, ugfx, SPI) → voir `probleme-hat-lcd.md`.
- [ ] **Interface graphique — NON TRANCHÉE (point critique)**. Essais successifs : labwc (trop minimal, illisible), wayfire (abandonné), **GNOME** (déployé+redémarré : correct mais **trop lent sur Pi 4**). Piste retenue : DE léger **XFCE / LXDE / LXQt** (bien connus) — MAIS inutilisables visuellement sans **thème complet préconfiguré** (GTK + icônes + curseur + fond + config panel). À faire : choisir le DE, embarquer un thème propre déclarativement, panel + menu + favoris navigation (opencpn, xygrib), auto-login, always-on. Profiler la lenteur GNOME (KMS/vc4, accel GL) en parallèle.
- [x] **Control head pypilot** : LCD **réactivé** (`pypilot.controlHead.lcd = "jlx12864"` → `pypilot_hat jlx12864`) suite à la migration nixos-raspberrypi (SPI ON + `ugfx.spiscreen` buildé). Option `"none"` toujours dispo (headless). Patch `pypilot-headless-lcd.patch` conservé (utile si `none`). **À valider au banc** : affichage réel + appairage RF 433.
- [ ] **OpenCPN — plugin pypilot NE S'AFFICHE PAS au banc** : la liste des plugins est **toujours vide**. Donc problème plus profond que l'ABI. État : packagé (build OK : `libpypilot_pi.so` + data), câblé via `symlinkJoin` (`.desktop`+icône gardés), et OpenCPN 5.14 lit bien `OPENCPN_PLUGIN_DIRS` (`plugin_paths.cpp:157`). À diagnostiquer au banc :
  - liste « vide » = onglet **catalogue** (téléchargeable, vide hors-ligne) ou onglet **installés** ? Le plugin doit apparaître dans *installés*.
  - les plugins **fournis** par OpenCPN (grib/dashboard/wmm/chartdldr, dans `opencpn/lib/opencpn`) apparaissent-ils ? Si non → OpenCPN ne trouve aucun plugin (pas seulement le nôtre).
  - le binaire lancé est-il bien le wrapper (`OPENCPN_PLUGIN_DIRS` positionné dans le process GUI) ? Vérifier `cat /proc/$(pidof opencpn)/environ`.
  - **log de démarrage OpenCPN** : tentatives de chargement / rejets de `.so` (version API, lib manquante).

## Retours banc — « à investiguer plus tard »

- [ ] **Puce GPS USB non reconnue** : relever VID:PID (`lsusb`), vérifier `gps.autodetectIds` / hotplug gpsd réel (`gpsdctl`), accès série du démon gpsd (groupe `dialout`).
- [ ] **Interface lente** (confirmé : GNOME nettement trop lent sur Pi 4) : profiler accel GL/KMS (`vc4`/`v3d`, `hardware.graphics`), Wayland vs X, services au boot. Lié au choix du DE ci-dessus (un DE léger devrait déjà aider).

## Retours banc — « moins grave »

- [ ] **Élaguer les paquets non essentiels** de l'image (build ISO long) : chromium/vlc/evince lourds en aarch64 émulé — rendre optionnels ou alléger la suite par défaut.
- [ ] **OpenCPN — connexions préconfigurées** : lecture SignalK (:3000) + écriture pypilot (instructions pilote). Compléter `opencpn.conf` (sérialisation `DataConnections` à valider sur la version installée).

## HAT / device-tree — MIGRÉ vers nixos-raspberrypi (à valider au banc)

Voir `doc/probleme-hat-lcd.md` et le comparatif `doc/comparatif-base-rpi.fr.md`.
Bascule faite côté build (évalue + paquets buildent sous nixpkgs 25.11) ; reste
le flash + validation matérielle.

- [x] **Base RPi pérenne** : migration `nvmd/nixos-raspberrypi` (firmware/kernel vendor). `flake.nix` : input ajouté, `nixpkgs` suit le leur (25.11), hôtes Pi via `nixos-raspberrypi.lib.nixosSystem` (board `raspberry-pi-4/5.{base,display-vc4}` + module `sd-image`). `hosts/rpi.nix` allégé (plus de `sd-image-aarch64` générique). `lab-vm` reste sur nixpkgs simple.
- [x] **SPI / I2C / disable-bt via `config.txt`** : `pypilot-hat.nix` → `hardware.raspberry-pi.config.all` (`base-dt-params.spi/i2c_arm`, `dt-overlays.disable-bt`). Bloc gardé par `optionalAttrs` (option absente sur lab-vm).
- [x] **`ugfx` `spiscreen`** : buildé sous 25.11 (pkg-config trouve libgpiod → `GPIOD_VERSION_MAJOR`). `hasattr(ugfx,'spiscreen')==True`.
- [ ] **VALIDATION BANC** (re-flash image vendor) : `/dev/spidev0.0` présent, LCD affiche, `i2cdetect -y 1` voit l'IMU (0x68), ttyAMA0 libéré (moteur), appairage RF.
- [~] **macarthur-hat** (lab-rpi5) : encore en `hardware.deviceTree.overlays` (évalue, mais à porter sur `config.txt` comme pypilot-hat quand on testera le Pi 5).
- Obsolète : nettoyage `config.txt` sur p1 (l'image vendor est régénérée au flash).

## Reste de la spec (Phase 6 / validation)

- [ ] **Plugins SignalK** pré-installés (`@signalk/zones`, `signalk-to-nmea2000`) — packaging npm déclaratif (en attendant : UI web).
- [ ] **ais.sdr** : tester `ais-catcher` sur dongle RTL-SDR réel (UDP :10110 → provider SDR), blacklist DVB + accès `plugdev`.
- [ ] **Checklist banc niveau 3** (cf. spec) : IMU `i2cdetect 0x68`, motor controller, GPS hotplug + chrony, AIS série, anti-veille écran.
- [ ] **macarthur-hat** : même correctif d'overlay (`&spi`, symboles) à reporter quand on testera lab-rpi5.

## OK (validé au banc)

- Boot OK ; SignalK OK (+ connexion pypilot) ; OpenCPN se lance ; connexion AIS à tester (pas d'AIS).
- Déploiement déclaratif OK ; clavier fr OK ; OpenCPN ne démarre plus tout seul ; control head démarre (gpiod).
