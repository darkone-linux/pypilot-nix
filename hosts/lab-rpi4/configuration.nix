# lab-rpi4 — Raspberry Pi 4 lab host, pypilot HAT.

{ ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi4";
  services.navigation.hardware = "pypilot-hat";

  # Bench display: chartplotter desktop (labwc, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.desktop.enable = true;
}
