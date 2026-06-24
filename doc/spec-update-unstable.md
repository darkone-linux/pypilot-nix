# Spécification — Userspace partiel sur nixpkgs unstable (26.11)

## Contexte et objectif

La chaîne de boot des hôtes Raspberry Pi est fournie par `nixos-raspberrypi`,
épinglé sur `nixos-25.11` (kernel, firmware, bootloader, device-tree). Aujourd'hui
**tout l'hôte Pi est en 25.11**, y compris les paquets applicatifs.

Objectif : pouvoir **choisir paquet par paquet** certains logiciels servis depuis
`nixpkgs` unstable (= `26.11-pre`) — pas seulement les paquets marins, mais
n'importe quel paquet, **dont `opencpn` et `opencpn-plugin-pypilot`** — tout en
gardant la chaîne de boot vendor 25.11. Le tout doit rester **réversible** et
offrir deux régimes au choix par hôte :

- **Mode « follow »** : tout suit `nixos-raspberrypi` (cohérent 25.11) — statu quo.
- **Mode « partiel »** : certains paquets, choisis explicitement, viennent de
  l'instance `unstable`.

Pas d'urgence : ce document fige le design avant implémentation.

---

## État actuel (vérifié par `nix eval`)

| Hôte | `system.nixos.release` | Origine des paquets |
|---|---|---|
| `navpi`, `lab-rpi4`, `lab-rpi5` | `25.11` | nixpkgs vendor de `nixos-raspberrypi` |
| `lab-vm` | `26.11` | input racine `nixpkgs` (`nixos-unstable`) |

- `mkRpiHost` (flake.nix:47) passe par `nixos-raspberrypi.lib.nixosSystem` : le
  `pkgs` du système est celui du vendor (25.11). `hosts/common.nix:31` applique
  l'overlay marin **sur ce pkgs 25.11** → les paquets marins du Pi sont en 25.11.
- L'input racine `nixpkgs = nixos-unstable` **est** `26.11-pre` ; il n'alimente
  aujourd'hui que les sorties `packages`/`checks`/`devShells` et `lab-vm`.
- `nvmd/nixos-raspberrypi` suit `main` (pin `nixos-25.11`). Branches amont
  disponibles : `nixos-unstable` (= 26.11-pre, vendor-intégré), `nixos-26.05`.
  **Pas encore de branche `nixos-26.11`** (sortie prévue ~novembre 2026).

Conséquence : un canary 26.11 existe déjà via `lab-vm`.

---

## Principe : une clé `unstable` générique

On expose aux modules et configs d'hôte une **instance pkgs complète** issue de
l'input racine unstable, étendue de l'overlay marin. Nommée `unstable` (et non
`marineUnstable`) car elle donne accès à **tout nixpkgs 26.11**, pas seulement
aux paquets marins.

```nix
# flake.nix — dans mkRpiHost, ajout à specialArgs
specialArgs = {
  inherit nixos-raspberrypi;

  # nixpkgs 26.11 (input racine) + overlay marin, arch aarch64. À piocher
  # paquet par paquet dans les configs d'hôte pour un userspace partiel ;
  # ignoré si l'hôte n'y touche pas (mode « follow »).
  unstable = nixpkgs.legacyPackages.aarch64-linux.extend marineOverlay;
};
```

Le même argument est passé à `mkVmHost` par cohérence (sur `lab-vm`, déjà 26.11,
`unstable` ≈ le `pkgs` du système : pioche neutre).

### Usage dans une config d'hôte

L'hôte reçoit `unstable` comme argument de module et choisit librement :

```nix
{ unstable, ... }:
{
  # Service marin depuis 26.11 (Tier 1, sûr).
  services.navigation.signalk.package = unstable.signalk-server;

  # Paquet quelconque de nixpkgs depuis 26.11.
  environment.systemPackages = [ unstable.xygrib ];

  # OpenCPN + son plugin depuis 26.11 (voir « Problème GL » et couplage ABI).
  services.navigation.opencpn = {
    package = unstable.opencpn;
    plugins = [ unstable.opencpn-plugin-pypilot ];
  };
}
```

Ne rien écrire = **mode follow** : tout reste en 25.11 vendor.

### Options de service réutilisées (déjà existantes)

| Option | Module | Défaut |
|---|---|---|
| `services.navigation.signalk.package` | signalk.nix:149 | `pkgs.signalk-server` |
| `services.navigation.pypilot.package` | pypilot.nix:51 | `pkgs.pypilot` |
| `services.navigation.opencpn.package` | opencpn.nix:68 | `pkgs.opencpn` |
| `services.navigation.opencpn.plugins` | opencpn.nix:92 | `[ ]` |

Aucune nouvelle option n'est strictement nécessaire : la clé `unstable` + les
options `package`/`plugins` existantes suffisent à un choix fin. (Un sucre
syntaxique optionnel est décrit plus bas.)

---

## Couplage ABI : OpenCPN et son plugin indissociables

`opencpn-plugin-pypilot` est un `.so` chargé par le binaire OpenCPN : il doit être
compilé contre **le même OpenCPN / wxGTK** (même nixpkgs). Donc :

> Si `opencpn.package = unstable.opencpn`, alors **obligatoirement**
> `opencpn.plugins = [ unstable.opencpn-plugin-pypilot ]` (jamais un mélange
> 25.11 / 26.11). La règle vaut pour tout futur plugin OpenCPN.

`finalPackage` (opencpn.nix:75) emballe `package` + `plugins` ; il reste l'unique
binaire à lancer (desktop, autostart). Inchangé par cette spec.

---

## Catégories de risque (tiers) et problème GL

Le seul vrai danger fonctionnel d'un userspace partiel est le **couplage au GL /
driver du système**. Le système graphique (mesa, drivers `vc4`/`v3d`, libglvnd)
provient de `hardware.graphics`, donc du vendor 25.11. Un paquet 26.11 qui fait
du GL embarque son propre `libGL`/wx/GTK (closure 26.11) mais charge au runtime
le **driver mesa du système (25.11)**.

| Tier | Paquets | Risque | Recommandation |
|---|---|---|---|
| **1** | `signalk-server`, `ais-catcher`, `canboat`, `nav-discover`, outils CLI | Faible (aucun GL) | OK depuis `unstable` |
| **2** | `pypilot` | Moyen : démon/web numpy/scipy OK ; GUI wx+OpenGL de calibration lie le GL | OK pour le démon ; **valider l'écran de calibration** sur banc |
| **3** | `opencpn` (+ plugin), stack desktop/`mesa`/labwc | Élevé : userspace GL ↔ driver vendor 25.11 | **Possible mais à valider impérativement sur matériel** |

### Problème GL en détail (Tier 2/3, dont OpenCPN demandé)

- **Dispatch glvnd** : `libglvnd` charge le driver via `dlopen`. L'ABI glvnd↔driver
  est généralement stable entre releases proches (25.11 ↔ 26.11), mais **non
  garanti** ; à vérifier au runtime, pas seulement au build.
- **Symboles GL legacy** : déjà un point sensible (cf. patch `pywavefront` côté
  pypilot). Une bascule de version GL peut réintroduire ce type de divergence.
- **Mismatch mesa** : on ne peut pas remplacer proprement le `mesa` système (lié
  aux drivers vendor `vc4`/`v3d` du firmware 25.11) sans casser le GL. Donc on
  garde mesa en 25.11 et on accepte qu'`opencpn` 26.11 tourne dessus.
- **Conséquence pratique** : `opencpn` depuis `unstable` **peut** fonctionner,
  mais c'est le cas qui exige la validation matériel la plus stricte (rendu des
  cartes, plugin pypilot, accélération GPU). Si le rendu casse, deux issues :
  1. revenir à `opencpn` 25.11 (mode follow pour ce paquet) ;
  2. envisager la migration complète (voir « Évolution future »).

---

## Sucre syntaxique optionnel (confort, non bloquant)

Pour éviter de répéter `unstable.` et documenter l'intention, un petit module
`modules/userspace-unstable.nix` peut déclarer :

- `services.navigation.unstablePackages` : liste de noms (`str`) de paquets de
  service à basculer en `unstable` d'un coup (mappe vers les options `package`
  via `mkForce`) ;
- garde le couplage OpenCPN/plugin cohérent automatiquement.

Règles AGENTS.md à respecter dans ce module : `mkIf`/`mkMerge`, pas de
`with lib`, `lib.x` explicite, ligne vide avant chaque commentaire.

**Décision** : sucre optionnel, à n'ajouter que si la liste manuelle devient
pénible. Le mécanisme `unstable` + options existantes reste la base.

---

## Risques généraux

- **Closure plus lourde** : chaque paquet 26.11 amène sa fermeture (glibc/python/
  node/wxGTK 26.11) en plus du 25.11 → +centaines de Mo sur la carte SD. OpenCPN
  + wxGTK est notablement lourd. À surveiller sur l'image.
- **Mismatch GL** : traité par les tiers ci-dessus (Tier 3 = validation stricte).
- **systemd reste 25.11** : un seul systemd (système 25.11) ; les paquets 26.11
  sont des binaires dans leur closure → pas de conflit de version systemd.
- **`stateVersion` inchangé** (`25.11`, common.nix:97) : le partiel userspace ne
  déclenche aucune migration d'état.
- **Dérive unstable** : 26.11-pre bouge ; `flake.lock` fige, mais chaque
  `nix flake update` peut casser un build. Mitigé par le canary `lab-vm`.

---

## Fichiers concernés

| Fichier | Changement |
|---|---|
| `flake.nix` | `mkRpiHost` (+ `mkVmHost`) : ajouter `unstable` aux `specialArgs` |
| `hosts/<hôte>/configuration.nix` | choix des paquets `unstable` (opt-in) |
| `modules/userspace-unstable.nix` (optionnel) | sucre `unstablePackages` |

Aucune modification des modules de service (`opencpn.nix`, `signalk.nix`,
`pypilot.nix`) : leurs options `package`/`plugins` existent déjà.

---

## Vérification (du moins risqué au plus risqué)

1. **Canary VM (déjà 26.11)** : `nix build .#packages.aarch64-linux.opencpn-plugin-pypilot`
   et les paquets Tier 1 — prouve les builds 26.11 aarch64. Démarrer `lab-vm`,
   vérifier les services basculés.
2. **Éval Pi** : après édition, `nix eval` de l'option `package` basculée pour
   confirmer qu'elle pointe une dérivation `26.11pre` et que le reste reste
   `25.11`. Puis `just clean` (fix + check + format) — règle AGENTS.md.
3. **Build image** : `nix build .#packages.aarch64-linux.lab-rpi4-sdImage` avec
   les bascules actives ; vérifier que kernel/firmware/bootloader restent vendor
   25.11.
4. **Banc matériel (niveau 3)** : déployer sur `lab-rpi4`. Vérifier :
   - Tier 1 : SignalK (UI web), AIS, services headless ;
   - Tier 2 : écran de calibration pypilot (GUI wx/OpenGL) ;
   - Tier 3 : **OpenCPN** — rendu des cartes, accélération GPU, chargement du
     plugin pypilot, connexion NMEA0183.
   Ne basculer `navpi` (prod) qu'après validation complète sur `lab-rpi4`.

---

## Évolution future (hors périmètre de cette spec)

Si trop de paquets GL (Tier 3) doivent passer en 26.11, le partiel devient
fragile : préférer alors la **migration complète** en pointant `nixos-raspberrypi`
sur sa branche `nixos-unstable` (= 26.11-pre, kernel+firmware+mesa vendor-intégrés
et cohérents). `stateVersion` conservé, validation matériel complète requise.
Étape intermédiaire stable possible : branche `nixos-26.05`. À reconsidérer quand
la branche `nixos-26.11` amont existera (~novembre 2026).
