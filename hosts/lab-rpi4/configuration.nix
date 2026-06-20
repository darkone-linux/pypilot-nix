# lab-rpi4 — Raspberry Pi 4 lab host, pypilot HAT.

{ pkgs, ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi4";
  services.navigation.hardware = "pypilot-hat";

  # Bench display: chartplotter desktop (labwc default, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.desktop.enable = true;

  # labwc by default; set compositor = "gnome" here to test the GNOME session.
  # services.navigation.desktop.compositor = "gnome";
}
