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
- [ ] **Essayer wayfire** (labwc jugé trop minimaliste : pas de menu, illisible). Ajouter wayfire au module desktop (compositeur configurable) + panneau/menu type Raspberry Pi OS (wf-shell / wf-panel). Basculer lab-rpi4 sur wayfire.
- [~] **Control head pypilot** : `pypilot_hat` démarre (fix gpiod/pillow) mais plante (LCD). LCD bloqué (cf. `probleme-hat-lcd.md`).
  - [ ] **Rendre `pypilot_hat` headless-safe** (LCD absent → ne pas planter ; keypad/RF/IR actifs) — **approuvé**, à faire. Débloque l'appairage de la télécommande RF 433.
- [ ] **OpenCPN — plugin pypilot** : ni activé, ni dans la liste des plugins dispo. Packager `opencpn-plugin-pypilot` (pypilot_pi) et le câbler via `services.navigation.opencpn.plugins`.

## Retours banc — « à investiguer plus tard »

- [ ] **Puce GPS USB non reconnue** : relever VID:PID (`lsusb`), vérifier `gps.autodetectIds` / hotplug gpsd réel (`gpsdctl`), accès série du démon gpsd (groupe `dialout`).
- [ ] **Interface plus lente qu'OpenPlotter** : profiler (compositeur Wayland sans accel ? services au boot ? `hardware.graphics`/`vc4` KMS ?).

## Retours banc — « moins grave »

- [ ] **Élaguer les paquets non essentiels** de l'image (build ISO long) : chromium/vlc/evince lourds en aarch64 émulé — rendre optionnels ou alléger la suite par défaut.
- [ ] **OpenCPN — connexions préconfigurées** : lecture SignalK (:3000) + écriture pypilot (instructions pilote). Compléter `opencpn.conf` (sérialisation `DataConnections` à valider sur la version installée).

## HAT / device-tree (DÉCISION ARCHI — mise de côté)

Voir `doc/probleme-hat-lcd.md`. `raspberry-pi-nix` écarté (non maintenu > 1 an).

- [ ] **Choisir une base RPi pérenne** : évaluer `nvmd/nixos-raspberrypi` (actif) ; ou tester le boot sans U-Boot (firmware → kernel direct, `config.txt` maîtrise le DTB) sur l'image générique.
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
