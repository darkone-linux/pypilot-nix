# lab-rpi4 — Raspberry Pi 4 lab host, pypilot HAT.

{ pkgs, ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi4";
  services.navigation.hardware.hats.enablePypilot = true;

  # Bench USB GPS on a Prolific PL2303 (generic serial chip, no dedicated GNSS
  # USB ID): pin it so gpsd adopts it on plug-in via /dev/gps0. The gps0 symlink
  # also makes pypilot's serialprobe skip the port, ending the open() contention.
  services.navigation.gps.vendorId = "067b";
  services.navigation.gps.productId = "2303";

  # AIS over SDR: the RTL-SDR Blog v4 dongle decodes AIS into Signal K. Wired
  # plug-and-play (udev starts ais-catcher when the dongle appears); the DVB
  # kernel driver is blacklisted so it does not grab the device.
  services.navigation.ais.sdr.enable = true;

  # Bench display: chartplotter desktop (labwc default, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.opencpn.enabledPlugins = [ "libpypilot_pi.so" ];
  services.navigation.desktop.enable = true;

  # On-box dev/admin toolbox: Zed editor + essentials, admin and Nix tooling.
  services.navigation.development.enable = true;

  # Bench gateway: route+NAT the LAN through end0, serve DHCP/DNS, and run the
  # on-board WiFi hotspot (ssid Lab-rpi4OnBoardWifi) bridged into the same LAN.
  #
  # Pi 4/5 name the onboard ethernet end0 (not eth0); the masquerade binds to
  # this exact name, so a wrong name silently breaks client NAT.
  services.navigation.network = {
    upstreamInterface = "end0";
    hotspot.enable = true;
  };

  # labwc by default; set compositor = "gnome" here to test the GNOME session.
  # services.navigation.desktop.compositor = "gnome";
}
