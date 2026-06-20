# Comparatif base RPi : nixos-raspberrypi vs nixos-hardware (LCD / SPI)

Style télégraphique. Résumé d'investigation — **aucune implémentation**, aide à
la décision archi (cf. `doc/probleme-hat-lcd.md`).

## Rappel du problème

- Image SD générique (`sd-image-aarch64`, U-Boot + extlinux) : les overlays
  device-tree **ne s'appliquent pas**.
- Cause : DTB du `FDTDIR` (kernel mainline) **sans `__symbols__`** → `&spi`,
  `&i2c1` non résolus ; `config.txt` firmware `dtparam=spi=on` sans effet via la
  chaîne U-Boot.
- Conséquence : pas de SPI (LCD du HAT), pas de `disable-bt` (UART moteur).
- `raspberry-pi-nix` (nix-community) : **écarté**, non maintenu > 1 an.

## Les deux candidats ne jouent PAS le même rôle

Point clé : ce ne sont pas deux solutions concurrentes au même problème.

### nixos-hardware (NixOS/nixos-hardware)

- **Nature** : collection de petits modules de *tweaks* matériels par appareil
  (`raspberry-pi/4` : GPU/VC4, firmware, quelques options kernel). Pas un
  système de boot, pas une distro.
- **Boot / device-tree** : n'apporte **rien** sur la chaîne de boot. On reste
  sur l'image générique (U-Boot) → **même blocage** que le nôtre.
- **Preuve** : issue #760 « RPi4 device tree overlay not applied » — DTB compilé
  correct, `/proc/device-tree` inchangé au runtime. **Ouverte, non résolue.**
- **Maintenance** : officiel nixos-community, **très actif**.
- **Verdict LCD/SPI** : **ne résout pas** le problème seul. Complémentaire, pas
  une réponse.

### nixos-raspberrypi (nvmd/nixos-raspberrypi)

- **Nature** : distro NixOS RPi **entièrement déclarative**, drop-in de
  `nixpkgs.lib.nixosSystem` (`nixos-raspberrypi.lib.nixosSystem*`).
- **Boot / device-tree** : utilise le **firmware + kernel vendor Raspberry Pi**
  (`raspberrypifw`) → DTBs vendor **avec `__symbols__`** + répertoire d'overlays,
  et `config.txt` **traduit en Nix** (`hardware.raspberry-pi.config`). Les
  `dtparam`/`dtoverlay` (SPI, `disable-bt`, i2c…) **s'appliquent réellement**.
  Bootloader configurable (`kernelboot` / `uboot` / `kernel`).
- **Maintenance** : **actif** (release `v1.20260517.0`, mai 2026 ; ~527 commits,
  575 ★).
- **Verdict LCD/SPI** : **voie qui débloque** SPI (LCD) et `disable-bt` (UART
  moteur) — exactement ce qui manque.

## Recommandation

1. **Pour le LCD/SPI : adopter `nixos-raspberrypi`** (firmware vendor). C'est le
   seul des deux qui adresse la cause (DTBs à symboles + `config.txt` appliqué).
2. **`nixos-hardware` reste utile en complément** (tweaks matériels), à empiler
   éventuellement par-dessus — mais ne le retenir **pas** comme réponse au LCD.

## Coût de migration (à prévoir, non chiffré ici)

- Nouvel input flake `nixos-raspberrypi` → **dégèle `flake.lock`** (fichier
  protégé : à faire explicitement, pas à la légère).
- `mkHost` : remplacer `nixpkgs.lib.nixosSystem` par le helper de la distro pour
  les hôtes Pi ; revoir `hosts/rpi.nix` (image SD vendor au lieu du
  `sd-image-aarch64` générique).
- Réécrire les overlays HAT en `hardware.raspberry-pi.config` (config.txt) +
  `dtoverlay` plutôt que `hardware.deviceTree.overlays`.
- Un **re-flash** du banc.
- Revalider toute la stack au banc (niveau 3) après bascule.

## Alternative sans changer de base (à tester, plus fragile)

- Boot firmware → kernel **direct** (sans U-Boot) sur l'image générique :
  `config.txt` reprend la main sur le DTB/overlays. Moins de churn (pas de
  nouvel input) mais hors des sentiers battus NixOS, à éprouver.

## Sources

- [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi)
- [nixos-hardware #760 — RPi4 overlay not applied](https://github.com/NixOS/nixos-hardware/issues/760)
- [nix-community/raspberry-pi-nix (écarté)](https://github.com/nix-community/raspberry-pi-nix)
- [NixOS Wiki — Raspberry Pi 4](https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_4)
