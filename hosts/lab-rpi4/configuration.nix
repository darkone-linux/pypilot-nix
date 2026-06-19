# lab-rpi4 — Raspberry Pi 4 lab host, pypilot HAT.
#
# Override compositor to wayfire for evaluation (see doc/todo.fr.md).
# Revert to labwc by commenting or removing the compositor line.

{ ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi4";
  services.navigation.hardware = "pypilot-hat";

  # Bench display: chartplotter desktop (wayfire, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.desktop.enable = true;
  services.navigation.desktop.compositor = "wayfire";
}
