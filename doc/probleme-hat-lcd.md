# Problème : écran LCD du HAT pypilot (control head) — investigation

Style télégraphique. Banc : `lab-rpi4` (Raspberry Pi 4, HAT pypilot).

## RÉSOLU (migration nixos-raspberrypi) — à valider au banc

Les deux causes profondes (SPI non appliqué, `ugfx` sans `spiscreen`) sont
levées côté build. Reste la validation matérielle (flash + banc).

- **Bascule sur `nvmd/nixos-raspberrypi`** (firmware vendor) — voir `flake.nix`,
  `comparatif-base-rpi.fr.md`. Les DTBs vendor ont `__symbols__` et `config.txt`
  s'applique vraiment.
- **SPI/I2C/disable-bt via `config.txt`** : `pypilot-hat.nix` pose
  `hardware.raspberry-pi.config.all` (`base-dt-params.spi="on"`,
  `i2c_arm="on"`, `dt-overlays.disable-bt`) → `/dev/spidev0.0` attendu.
- **`ugfx.spiscreen` désormais buildé** : sous nixpkgs 25.11, `pkg-config
  --cflags libgpiod` réussit au build → `-DGPIOD_VERSION_MAJOR` défini → la
  classe `spiscreen` (sous `#ifdef`) est exposée. Vérifié :
  `hasattr(ugfx,'spiscreen') == True`.
- **Driver LCD réactivé** : `pypilot.controlHead.lcd = "jlx12864"` (défaut) →
  `pypilot_hat jlx12864`.

Ce qui suit est l'investigation d'origine (image générique), conservée pour
mémoire.

## Symptôme

- Aucun affichage sur le LCD du HAT.
- `pypilot-hat.service` en échec / inactif (control head : LCD + keypad + IR + RF 433).

## Diagnostic — deux causes indépendantes

### Cause 1 — `gpiod`/`pillow` manquants (RÉSOLU)

- `pypilot_hat` → `ModuleNotFoundError: No module named 'gpiod'`.
- pypilot utilise l'API **libgpiod v2** (`gpiod.request_lines`, `gpiod.LineSettings`, `gpiod.line`) et son extra `[hat]` exige `gpiod` + `pillow` (cf. METADATA : `Requires-Dist: gpiod; extra == "hat"`, `pillow; extra == "hat"`).
- **Fix** : ajout de `python3Packages.gpiod` (v2.x) + `pillow` aux `dependencies` de `pkgs/pypilot.nix`. Vérifié : présents dans le PYTHONPATH du wrapper `pypilot_hat`.
- Annexe : `pypilot_hat` shelle vers `renice` (non fatal) → `path = [ pkgs.util-linux ]` ajouté au service.

Après ce fix, `pypilot_hat` démarre puis plante plus loin (causes 2 et 3).

### Cause 2 — SPI non activé : les overlays device-tree ne s'appliquent pas (BLOQUÉ)

- `/dev/spidev*` absent ; tous les nœuds `spi@*` à `status = "disabled"` dans le DT live.
- Notre overlay `pypilot-hat-spi0` ciblait `&spi0` et `&spidev0` — **symboles inexistants** dans le DTB mainline. Symboles réels relevés sur le banc :
  - `spi` → `/soc/spi@7e204000` (= SPI0), `spi1`..`spi6`, pas de `spi0`, pas de `spidev0`.
  - `i2c1` → `/soc/i2c@7e804000` (I2C marche, mais probablement activé **par défaut**, pas par notre overlay).
- Overlay corrigé (commité) : cible `&spi` + nœud `spidev@0` inline (`compatible = "rohm,dh2228fv"`). **Sans effet** après déploiement + reboot.

**Pourquoi ça ne marche pas (cœur du problème) :**

- Le DTB du `FDTDIR` (kernel mainline, `device-tree-overlays/broadcom/bcm2711-rpi-4-b.dtb`) **ne contient pas `__symbols__`** (`strings … | grep -c __symbols__` = 0).
- Sans `__symbols__`, `hardware.deviceTree.overlays` **ne peut pas résoudre** les références `&spi`/`&i2c1` → overlays silencieusement **non appliqués** (le DTB du store ne contient ni `spidev` ni `rohm`).
- Le DT live, lui, **a** des `__symbols__` → le kernel tourne donc avec un AUTRE DTB que celui du `FDTDIR` (vraisemblablement celui de la partition firmware `p1`, qui a les symboles).
- MAIS ajouter `dtparam=spi=on` au `config.txt` firmware (p1) + reboot → SPI **toujours** `disabled`.

**Conclusion** : sur cet enchaînement de boot (firmware RPi → U-Boot → DTB), **aucun** levier déclaratif testé n'active SPI :
- ni `hardware.deviceTree.overlays` (DTB FDTDIR sans symboles),
- ni `config.txt` firmware `dtparam=spi=on`.

Le DTB réellement vu par le kernel est opaque/non maîtrisé. Tout besoin DT du HAT est concerné : **SPI (LCD), mais aussi `disable-bt`** (libération de ttyAMA0 pour le motor controller).

### Cause 3 — `ugfx` compilé sans `spiscreen` (BLOQUÉ, packaging)

- Même SPI activé, `pypilot_hat` planterait : `AttributeError: module 'pypilot.hat.ugfx.ugfx' has no attribute 'spiscreen'` (dans `hat/lcd.py` : `screen = ugfx.spiscreen(0)`).
- L'extension SWIG `ugfx` de notre paquet pypilot est buildée **sans** le code `spiscreen` (pilote LCD SPI). À investiguer dans le `setup.py` de pypilot (condition de compilation, dépendance manquante, détection de carte).

## Chaîne de boot observée (image générique)

```
firmware RPi (start4.elf) lit /boot(p1, FAT)/config.txt
   → [pi4] kernel=u-boot-rpi4.bin   (charge U-Boot + un DTB AVEC __symbols__)
U-Boot lit /(p2, ext4)/boot/extlinux/extlinux.conf
   → LINUX …-Image, INITRD …, FDTDIR …-device-tree-overlays   (DTB mainline SANS __symbols__)
```

- Partition firmware : `mmcblk0p1` (30 Mo, vfat), **non montée** en fonctionnement ; non gérée par `nixos-rebuild` (écrite au build de l'image SD seulement).
- `config.txt` firmware : `[pi4] kernel=u-boot-rpi4.bin`, `enable_uart=1`, `arm_64bit=1`, `armstub8-gic.bin`, etc.

## Solutions envisagées — recherche d'une solution pérenne

Contrainte : **`nix-community/raspberry-pi-nix` n'est plus maintenu (> 1 an)** → écarté. Besoin d'une base pérenne.

1. **`nvmd/nixos-raspberrypi`** (à évaluer en priorité) — apparemment actif ; kernel/firmware RPi, `config.txt` + overlays déclaratifs qui s'appliquent réellement. Déjà cité dans la spec. Coût : nouvel input flake (dégèle `flake.lock`), refonte image/boot, un re-flash.
2. **Boot sans U-Boot** — configurer le firmware pour booter le kernel directement (`kernel=<vmlinux>` au lieu de `u-boot-rpi4.bin`) → `config.txt` (`dtparam`, `dtoverlay`) contrôle alors le DTB vu par le kernel. C'est en gros ce que font les solutions RPi dédiées. À tester sur l'image générique.
3. **DTB mainline avec symboles** — rebuild des DTB kernel avec `-@` (symbols) pour que `hardware.deviceTree.overlays` s'applique. Fragile, dépend du build kernel.
4. **Gérer `config.txt` au build d'image** (générique) — non déclaratif au quotidien (re-flash par changement matériel).

Recommandation à creuser : **évaluer `nvmd/nixos-raspberrypi`** (option 2 en test rapide si on veut rester sur l'image générique).

## Reproduction / commandes utiles (banc)

```sh
# Symboles DT réels
ssh root@lab-rpi4 'ls /sys/firmware/devicetree/base/__symbols__/ | grep spi'
ssh root@lab-rpi4 'tr -d "\0" < /sys/firmware/devicetree/base/__symbols__/spi'   # -> /soc/spi@7e204000

# Statut SPI live
ssh root@lab-rpi4 'tr -d "\0" < /proc/device-tree/soc/spi@7e204000/status'        # -> disabled

# DTB FDTDIR sans symboles / sans overlay
ND=$(grep -o 'FDTDIR [^ ]*' /boot/extlinux/extlinux.conf | head -1)
ssh root@lab-rpi4 "strings /boot/.../bcm2711-rpi-4-b.dtb | grep -c __symbols__"    # -> 0

# Partition firmware (non montée)
ssh root@lab-rpi4 'lsblk; mount -o ro /dev/mmcblk0p1 /tmp/fw; cat /tmp/fw/config.txt'
```

## État / modifications laissées

- `pkgs/pypilot.nix` : `gpiod` + `pillow` + `util-linux`(renice) — **gardés** (corrects).
- `modules/hardware/pypilot-hat.nix` : overlay SPI corrigé (`&spi` + `spidev@0`) — **gardé** (inerte tant que le DT ne s'applique pas, correct une fois le boot réglé).
- **Modif manuelle** `config.txt` sur p1 (`dtparam=spi=on`, inerte) — à nettoyer/écraser au prochain re-flash.

## Prochaines étapes

- Décision archi HAT/DT (cf. solutions ci-dessus) — **mise de côté** pour l'instant (choix utilisateur).
- `pypilot_hat` headless-safe — **FAIT** : LCD désactivé via l'option `pypilot.controlHead.lcd` (défaut `"none"` → lance `pypilot_hat none`, driver `none` déjà supporté par `lcd.py`, n'appelle jamais `ugfx.spiscreen`). Plus de crash ; keypad/IR/RF restent actifs (processus principal). Patch `pkgs/pypilot-headless-lcd.patch` : met le sous-processus LCD en veille au lieu de saturer un cœur (`poll()` court-circuite avant son `sleep` quand `screen is None`). Repasser l'option sur le modèle de dalle (`"jlx12864"`) une fois SPI fonctionnel.
- Corriger le build `ugfx` (`spiscreen`) une fois le DT/SPI fonctionnel.
