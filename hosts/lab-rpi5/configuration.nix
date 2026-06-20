# lab-rpi5 — Raspberry Pi 5 (experimental) lab host, MacArthur HAT.
#
# The generic aarch64 SD image targets the Pi 3/4 boot flow; Pi 5 has a
# different boot chain and is experimental here (no raspberry-pi-nix input).
# Booting must be validated on real hardware.

{ pkgs, ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi5";
  services.navigation.hardware = "macarthur-hat";

  # Bench display: chartplotter desktop (labwc, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.desktop.enable = true;
}
