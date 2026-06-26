# lab-rpi5 — Raspberry Pi 5 (experimental) lab host, MacArthur HAT.
#
# On the nixos-raspberrypi vendor base (raspberry-pi-5 board module). The HAT
# still uses hardware.deviceTree.overlays here; port it to
# hardware.raspberry-pi.config (config.txt) like pypilot-hat when the Pi 5 is
# tested on real hardware.

{ pkgs, ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi5";
  services.navigation.hardware.hats.enableMacArthur = true;

  # Bench display: chartplotter desktop (labwc, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.opencpn.enabledPlugins = [ "libpypilot_pi.so" ];
  services.navigation.desktop.enable = true;
}
