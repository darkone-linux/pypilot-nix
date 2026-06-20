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
- [x] **Essayer wayfire** (labwc jugé trop minimaliste : pas de menu, illisible). Ajouter wayfire au module desktop (compositeur configurable) + panneau/menu type Raspberry Pi OS (wf-shell / wf-panel). Basculer lab-rpi4 sur wayfire.
- [x] **Control head pypilot headless-safe** : LCD désactivé (option `pypilot.controlHead.lcd = "none"` → `pypilot_hat none`). Plus de crash ; keypad/IR/RF actifs (processus principal, indépendant du LCD) → appairage RF 433 possible via l'UI web. Patch `pypilot-headless-lcd.patch` : sous-processus LCD en veille au lieu de boucler. Repasser à `"jlx12864"` quand SPI fonctionnera.
- [~] **OpenCPN — plugin pypilot** : packagé (`pkgs/opencpn-plugin-pypilot.nix`, build OK : `libpypilot_pi.so` + data) et câblé via `services.navigation.opencpn.plugins`. Câblage **corrigé** : `opencpnPkg` passait de `runCommand` (ne gardait que `bin/opencpn` → perdait `.desktop`/icône, donc pas de lanceur GNOME et env plugin non transmis depuis la grille) à `symlinkJoin` (garde `.desktop`+icône, wrappe le binaire). Vérifié : OpenCPN 5.14 lit bien `OPENCPN_PLUGIN_DIRS` (`plugin_paths.cpp:157`) + `XDG_DATA_DIRS`. **Reste à valider au banc** : compat ABI/API → le plugin doit apparaître dans la liste et s'activer.

## Retours banc — « à investiguer plus tard »

- [ ] **Puce GPS USB non reconnue** : relever VID:PID (`lsusb`), vérifier `gps.autodetectIds` / hotplug gpsd réel (`gpsdctl`), accès série du démon gpsd (groupe `dialout`).
- [ ] **Interface plus lente qu'OpenPlotter** : profiler (compositeur Wayland sans accel ? services au boot ? `hardware.graphics`/`vc4` KMS ?).

## Retours banc — « moins grave »

- [ ] **Élaguer les paquets non essentiels** de l'image (build ISO long) : chromium/vlc/evince lourds en aarch64 émulé — rendre optionnels ou alléger la suite par défaut.
- [ ] **OpenCPN — connexions préconfigurées** : lecture SignalK (:3000) + écriture pypilot (instructions pilote). Compléter `opencpn.conf` (sérialisation `DataConnections` à valider sur la version installée).

## HAT / device-tree (DÉCISION ARCHI — mise de côté)

Voir `doc/probleme-hat-lcd.md` et le comparatif `doc/comparatif-base-rpi.fr.md`.
`raspberry-pi-nix` écarté (non maintenu > 1 an).

- [ ] **Choisir une base RPi pérenne** : comparatif fait → `nvmd/nixos-raspberrypi` (firmware vendor, DTBs à `__symbols__`, `config.txt` appliqué) débloque SPI ; `nixos-hardware` ne résout PAS (mêmes overlays non appliqués, issue #760). Reste à trancher : migrer vers nixos-raspberrypi (dégèle `flake.lock`, re-flash) ou tester le boot firmware→kernel direct sur l'image générique.
- [ ] **SPI / LCD** : dépend de la décision ci-dessus (overlay `&spi` déjà prêt, inerte tant que le DT ne s'applique pas).
- [ ] **`disable-bt` (motor controller sur ttyAMA0)** : même blocage DT que SPI → lié à la même décision.
- [ ] **`ugfx` sans `spiscreen`** : corriger le build pypilot (pilote LCD SPI) une fois SPI fonctionnel.
- [ ] **Nettoyer** la modif manuelle `config.txt` sur p1 (`dtparam=spi=on`, inerte) au prochain re-flash.

## Reste de la spec (Phase 6 / validation)

- [ ] **Plugins SignalK** pré-installés (`@signalk/zones`, `signalk-to-nmea2000`) — packaging npm déclaratif (en attendant : UI web).
- [ ] **ais.sdr** : tester `ais-catcher` sur dongle RTL-SDR réel (UDP :10110 → provider SDR), blacklist DVB + accès `plugdev`.
- [ ] **Checklist banc niveau 3** (cf. spec) : IMU `i2cdetect 0x68`, motor controller, GPS hotplug + chrony, AIS série, anti-veille écran.
- [ ] **macarthur-hat** : même correctif d'overlay (`&spi`, symboles) à reporter quand on testera lab-rpi5.

## OK (validé au banc)

- Boot OK ; SignalK OK (+ connexion pypilot) ; OpenCPN se lance ; connexion AIS à tester (pas d'AIS).
- Déploiement déclaratif OK ; clavier fr OK ; OpenCPN ne démarre plus tout seul ; control head démarre (gpiod).
