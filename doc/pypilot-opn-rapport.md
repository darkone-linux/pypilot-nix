# Rapport — Plugin pypilot dans OpenCPN

Contexte : OpenCPN 5.12.4, wx 3.2.8.1, sur lab-rpi4 (labwc). Plugin
`opencpn-plugin-pypilot` 0.7.0 (pypilot_pi). Objectifs : plugin visible + connexion
SignalK déclarative.

## CAUSE RACINE TROUVÉE (le wrapper était contourné)

Le banc lançait le **binaire opencpn brut** (`…opencpn-5.12.4/bin/opencpn`, PID
systemd), **pas** le wrapper `opencpn-with-plugins/bin/opencpn`. Or seul le
wrapper pose `OPENCPN_PLUGIN_DIRS`. Sans lui, OpenCPN scanne son propre
`lib/opencpn` (4 greffons intégrés) → pypilot n'est même pas candidat.

- Preuve : log du jour « Found **4** candidates » (chartdldr, wmm, dashboard,
  grib) ; pypilot absent. Les anciens « Found 5 » venaient d'un lancement manuel
  `opencpn` au terminal (= wrapper via PATH).
- Bug : `modules/desktop/labwc.nix` et `gnome.nix` lançaient
  `${opencpn.package}/bin/opencpn` (paquet brut) au lieu du wrapper.

### Correctif appliqué

- `modules/opencpn.nix` : option lecture seule `finalPackage` = paquet wrappé.
- `labwc.nix` + `gnome.nix` : lancent `opencpn.finalPackage` (boutons waybar,
  keybind, autostart) → `OPENCPN_PLUGIN_DIRS` posé, pypilot redevient candidat.
- `modules/pypilot.nix` : `pypilot_*` ajoutés à `systemPackages` (étaient
  injoignables en CLI ; le daemon tournait depuis son chemin de store).

### À revalider au banc (relancer OpenCPN via le bouton/menu)

- Log attendu : « Found 5 candidates » + pypilot chargé.
- Si pypilot **se charge mais reste invisible** dans Options→Plugins : voir
  ci-dessous (ABI `unknown:unknown`), workaround `OPENCPN_COMPAT_TARGET`.

## Note version OpenCPN (le « unstable » ne change rien sur le Pi)

- Pi : opencpn **5.12.4** (nixpkgs *vendor* de nixos-raspberrypi). unstable a
  **5.14.0**. Aligner l'input `nixpkgs` sur unstable n'y change rien : les hôtes
  Pi (`mkRpiHost`) se construisent sur le nixpkgs vendor, pas sur notre input.
- Pas un problème d'architecture CPU. Pour passer en 5.14 il faudrait surcharger
  `opencpn` depuis unstable dans l'overlay — risqué : l'ABI greffon
  (opencpn-libs pinné pour 5.12) peut casser. À décider séparément.

## État précédent (conservé)

- **Liste des plugins revenue** (grib, dashboard, wmm, chartdldr s'affichent).
- Connexion SignalK : seed corrigé (24 champs), pas encore validé à l'IHM.

## Corrections déjà appliquées (commit `2dd5c90`, `modules/opencpn.nix`)

1. **Chemin des plugins** — cause racine du « aucun plugin » :
   `model/src/plugin_paths.cpp` : `OPENCPN_PLUGIN_DIRS` **remplace** les chemins par
   défaut. L'ancien wrapper le fixait aux seuls dossiers externes → OpenCPN
   abandonnait ses plugins intégrés.
   - Fix : `symlinkJoin` inclut maintenant `cfg.plugins` ; `OPENCPN_PLUGIN_DIRS`
     pointe vers le dossier combiné (`$out/lib/opencpn`) contenant les **5 .so**.
   - Vérifié : log montre « Found 5 candidates » + « Loading PlugIn » pour les 5,
     dont `libpypilot_pi.so`, avec « Plugin is compatible: true ».

2. **Connexion SignalK déclarative** — format invalide :
   `gui/src/navutil.cpp` lit `DataConnections` (séparateur `|`), chaque entrée =
   24 champs `ConnectionParams::Serialize` (conn_params.cpp). L'ancien
   `0;2;localhost;10110;0;0` (6 champs, mauvais énums) → « Skipped invalid
   DataStream config ».
   - Énums (conn_params.h) : Type {SERIAL=0, NETWORK=1} ; NetProtocol {TCP=0,
     UDP=1, GPSD=2, SIGNALK=3} ; DataProtocol {NMEA0183=0, NMEA2000=1, SIGNALK=2}.
   - Nouveau seed (vérifié au store) :
     `1;3;localhost;3000;2;;0;0;0;0;;0;;0;0;0;0;1;Signal K;0;;0;0;`
   - Semé via tmpfiles `C` (si absent) → ne s'applique pas sur un `opencpn.conf`
     existant. Reset nécessaire au banc pour tester ; appliqué sur image neuve.

## Problème ouvert : pypilot chargé mais invisible

Faits établis par le source OpenCPN 5.12.4 + log :

- pypilot **se charge** (compatible, ~74 ms, pas de crash, pas de message d'erreur).
- `GetInstalled()` (pluginmanager.cpp:2505) renvoie **tous** les plugins de
  `GetPlugInArray()` **sans filtre** (renseigne juste `m_managed_metadata` via
  `MetadataByName`, vide si absent du catalogue).
- `PluginListPanel::ReloadPluginPanels` ajoute tous les `GetInstalled()` (actifs
  puis inactifs) ; `AddPlugin(PlugInData)` ne filtre pas non plus.
- Donc, en théorie, pypilot devrait apparaître.

Différence connue pypilot vs intégrés : les intégrés figurent dans le catalogue
`share/opencpn/ocpn-plugins.xml`, **pas** pypilot (`m_managed_metadata` vide).

Piste en cours (interrompue) : lire `LoadPlugIn` (plugin_loader.cpp ~1498+) pour
vérifier si, **après** « Loading PlugIn », le plugin peut être rejeté / non poussé
dans le tableau (blacklist, symboles `create_pi`/`destroy_pi` manquants, version
d'API). Aucun message de rejet n'apparaît dans le log jusqu'ici — à confirmer.

## Hypothèses restantes à départager

1. **Métadonnées catalogue requises** par l'IHM « managed » pour rendre un panneau
   non vide → fournir une entrée pour pypilot (`ocpn-plugins.xml` /
   `~/.opencpn/plugins/install_data/…`).
2. **Rejet silencieux post-chargement** (symbole, version d'API du plugin trop
   ancienne vs 5.12, ABI wx) → pypilot pas réellement dans le tableau affiché.
3. **Panneau créé mais à hauteur nulle** (nom/version/icône vides).

## ABI catalogue « unknown:unknown » (si invisible persiste)

OpenCPN calcule un tuple `target:version` (défini au build via `PKG_TARGET`).
Build Nix → souvent `unknown:unknown`. Impacte surtout le catalogue *managed* ;
un greffon local chargé devrait quand même s'afficher. Si ce n'est pas le cas :

- Diagnostic : lancer `opencpn --loglevel debug`, rafraîchir, chercher la ligne
  « Host: init: abi » (l'ABI attendue) dans `PluginHandler.cpp`.
- Workaround : `OPENCPN_COMPAT_TARGET=<target>:<version>` (ex.
  `debian-arm64:12`) force la compat. Posable via le wrapper `symlinkJoin`
  (`--set OPENCPN_COMPAT_TARGET …`) dans `modules/opencpn.nix` si confirmé utile.

## Prochaines étapes

- **D'abord** : relancer OpenCPN au banc via le bouton (wrapper) → confirmer
  « Found 5 » + pypilot visible. Le bug du lanceur masquait peut-être tout.
- Finir la lecture de `LoadPlugIn` (rejet post-chargement ?).
- Comparer la version d'API déclarée par pypilot_pi (opencpn-libs pinné) vs ce
  qu'attend 5.12.
- Tester l'ajout d'une métadonnée catalogue pypilot.
- Valider la connexion SignalK après reset de `~/.opencpn/opencpn.conf`.

## Repères

- Log : `~/.opencpn/opencpn.log` (skipper@lab-rpi4).
- Paquet plugin : `pkgs/opencpn-plugin-pypilot.nix` (rev pypilot_pi
  `1f53b4d`, opencpn-libs `6a29da6`).
- Module : `modules/opencpn.nix`.
