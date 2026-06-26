# Aggregator for the pure unit test suites (nix-unit format).
# Exposed in flake.nix as .#libTests; run with `just test`.

{ lib }:
let
  navLib = import ../../lib { inherit lib; };
in
{
  lib_hardware = import ./lib/hardware_test.nix { inherit navLib; };
}
