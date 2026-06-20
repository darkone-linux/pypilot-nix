# Custom marine-navigation packages. Takes a nixpkgs instance and returns the
# package set wired with its internal dependencies.
#
# `prev` is the previous overlay level — use it to reference un-overridden
# nixpkgs packages from within this overlay without infinite recursion.

final: _prev:
let
  py = final.python3Packages;

  rtimulib2 = py.callPackage ./rtimulib2.nix { };
  pypilot-data = py.callPackage ./pypilot-data.nix { };
in
{
  inherit rtimulib2 pypilot-data;

  pypilot = py.callPackage ./pypilot.nix { inherit rtimulib2 pypilot-data; };

  signalk-server = final.callPackage ./signalk-server.nix { };

  ais-catcher = final.callPackage ./ais-catcher.nix { };

  opencpn-plugin-pypilot = final.callPackage ./opencpn-plugin-pypilot.nix { };
}
