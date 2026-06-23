# lab-rpi4 — Raspberry Pi 4 lab host, pypilot HAT.

{ pkgs, ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi4";
  services.navigation.hardware = "pypilot-hat";

  # Bench USB GPS on a Prolific PL2303 (generic serial chip, no dedicated GNSS
  # USB ID): pin it so gpsd adopts it on plug-in via /dev/gps0. The gps0 symlink
  # also makes pypilot's serialprobe skip the port, ending the open() contention.
  services.navigation.gps.vendorId = "067b";
  services.navigation.gps.productId = "2303";

  # Bench display: chartplotter desktop (labwc default, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.desktop.enable = true;

  # On-box dev/admin toolbox: Zed editor + essentials, admin and Nix tooling.
  services.navigation.development.enable = true;

  # labwc by default; set compositor = "gnome" here to test the GNOME session.
  # services.navigation.desktop.compositor = "gnome";
}
