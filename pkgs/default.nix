# Custom marine-navigation packages, as a nixpkgs overlay.
#
# Mostly additive: packages are built from `final` (the fixpoint, so any
# override composes); `prev` is used only to wrap an existing nixpkgs package
# (xygrib). Imported directly as the flake's overlays.default and applied by
# hosts/common.nix.

final: prev:
let
  py = final.python3Packages;

  rtimulib2 = py.callPackage ./rtimulib2.nix { };
  pypilot-data = py.callPackage ./pypilot-data.nix { };

  # visualization.py pulls the legacy fixed-function GL symbols (GL_V3F,
  # glInterleavedArrays, …) from pyglet, which dropped them in 2.x — import dies
  # with "name 'GL_V3F' is not defined" and pypilot's boat plot silently
  # degrades. The patch sources GL from PyOpenGL (the context pypilot already
  # draws in) and replaces the unusable glInterleavedArrays path with an
  # immediate-mode display list.
  pywavefront = py.pywavefront.overridePythonAttrs (old: {
    dependencies = (old.dependencies or [ ]) ++ [ py.pyopengl ];

    patches = (old.patches or [ ]) ++ [ ./pywavefront-pyopengl-immediate.patch ];
  });
in
{
  inherit rtimulib2 pypilot-data;

  pypilot = py.callPackage ./pypilot.nix {
    inherit rtimulib2 pypilot-data pywavefront;

    # `libgpiod` resolves to the python binding under py.callPackage; pin the C
    # library (SWIG GPIO build) explicitly, and pass the binding as `gpiod`
    # (importable as `gpiod`, libgpiod v2) for the HAT control head.
    libgpiod = final.libgpiod;
    gpiod = py.libgpiod;
  };

  signalk-server = final.callPackage ./signalk-server.nix { };

  ais-catcher = final.callPackage ./ais-catcher.nix { };

  canboat = final.callPackage ./canboat.nix { };

  nav-discover = final.callPackage ./nav-discover.nix { };

  opencpn-plugin-pypilot = final.callPackage ./opencpn-plugin-pypilot.nix { };

  # XyGrib ships its data (coastline/relief maps + toolbar icons) under
  # `$out/XyGrib/data`, but its data-dir search never finds it on NixOS: the
  # binary's "look next to me" path resolves to `/nix` and nothing else matches,
  # so the app runs with no background map AND blank/black toolbar icons.
  # Fix without a rebuild: expose the tree under `<share>/xygrib/data` (where the
  # XDG_DATA_DIRS search looks) and bake that share dir into the binary's own
  # XDG_DATA_DIRS — the labwc session passes an empty one, so relying on the
  # system profile is not enough. Once found, maps and icons both work.
  xygrib =
    let
      base = prev.xygrib;
    in
    final.symlinkJoin {
      name = "xygrib-mapdata-${base.version}";
      paths = [ base ];
      nativeBuildInputs = [ final.makeWrapper ];
      postBuild = ''
        mkdir -p "$out/share/xygrib"
        ln -s ${base}/XyGrib/data "$out/share/xygrib/data"

        rm "$out/bin/xygrib"
        makeWrapper ${base}/bin/xygrib "$out/bin/xygrib" \
          --prefix XDG_DATA_DIRS : "$out/share"
      '';
    };
}
