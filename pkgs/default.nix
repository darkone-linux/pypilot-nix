# Custom marine-navigation packages. Takes a nixpkgs instance and returns the
# package set wired with its internal dependencies.

pkgs:
let
  py = pkgs.python3Packages;

  rtimulib2 = py.callPackage ./rtimulib2.nix { };
  pypilot-data = py.callPackage ./pypilot-data.nix { };
in
{
  inherit rtimulib2 pypilot-data;

  pypilot = py.callPackage ./pypilot.nix { inherit rtimulib2 pypilot-data; };

  signalk-server = pkgs.callPackage ./signalk-server.nix { };
}
