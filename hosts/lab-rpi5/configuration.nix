# lab-rpi5 — Raspberry Pi 5 (experimental) lab host, MacArthur HAT.
#
# On the nixos-raspberrypi vendor base (raspberry-pi-5 board module). The HAT
# still uses hardware.deviceTree.overlays here; port it to
# hardware.raspberry-pi.config (config.txt) like pypilot-hat when the Pi 5 is
# tested on real hardware.

{ pkgs, ... }:

{
  networking.hostName = "lab-rpi5";
  services.navigation.hardware.hats.enableMacArthur = true;

  # Bench display: chartplotter desktop (labwc, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.opencpn.enabledPlugins = [ "libpypilot_pi.so" ];
  services.navigation.desktop.enable = true;

  # Complementary options (uncommented per bench need):
  #
  # - Expose Signal K to the boat network (chartplotters, tablets):
  #   services.navigation.signalk.openFirewall = true;
  # - Pin a USB GPS by its lsusb ID so gpsd adopts /dev/gps0 on plug-in:
  #   services.navigation.gps.vendorId = "067b";
  #   services.navigation.gps.productId = "2303";
  # - On-box dev toolbox / AI agents:
  #   services.navigation.development.enable = true;
  #   services.navigation.development.ai = true;
}
