# navigation library (`navLib`) — pure helpers shared across the modules.
#
# Entry point aggregating the per-subject helper files. Namespaced so callers
# write `navLib.hardware.gpioConflicts`, leaving room for more subjects.

{ lib }:
let
  hardware = import ./hardware.nix { inherit lib; };
  serial = import ./serial.nix { inherit lib; };
in
{
  inherit hardware serial;
}
