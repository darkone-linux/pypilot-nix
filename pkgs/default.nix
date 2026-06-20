# Custom marine-navigation packages, as a nixpkgs overlay.
#
# Additive only: every package is built from `final` (the fixpoint, so any
# override composes), so the previous level `_prev` is unused. Imported directly
# as the flake's overlays.default and applied by hosts/common.nix.

final: _prev:
let
  py = final.python3Packages;

  rtimulib2 = py.callPackage ./rtimulib2.nix { };
  pypilot-data = py.callPackage ./pypilot-data.nix { };
in
{
  inherit rtimulib2 pypilot-data;

  pypilot = py.callPackage ./pypilot.nix {
    inherit rtimulib2 pypilot-data;

    # `libgpiod` resolves to the python binding under py.callPackage; pin the C
    # library (SWIG GPIO build) explicitly, and pass the binding as `gpiod`
    # (importable as `gpiod`, libgpiod v2) for the HAT control head.
    libgpiod = final.libgpiod;
    gpiod = py.libgpiod;
  };

  signalk-server = final.callPackage ./signalk-server.nix { };

  ais-catcher = final.callPackage ./ais-catcher.nix { };

  opencpn-plugin-pypilot = final.callPackage ./opencpn-plugin-pypilot.nix { };
}
