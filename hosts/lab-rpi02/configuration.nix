# lab-rpi02 — Raspberry Pi Zero 2 W lab host, wifi + Camera Module 3 Wide.
#
# Headless, RAM-constrained (512 MB) sensor node: no chartplotter desktop, no
# autopilot HAT. Reaches the boat network over the onboard wifi and streams the
# CSI camera through libcamera.

{ lib, ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi02";

  # Camera Module 3 Wide on the CSI connector (no header GPIO, see the module).
  services.navigation.hardware.modules.enableCamera3Wide = true;

  # Onboard Cypress wifi: brcmfmac firmware ships with linux-firmware, not the
  # vendor base, so pull it in explicitly.
  hardware.enableRedistributableFirmware = true;

  # Join the boat network with wpa_supplicant (lighter than NetworkManager on
  # the Zero 2). The PSK stays out of the store: @psk_BoatWifi@ is substituted
  # at boot from the secrets file, which holds one `KEY=passphrase` line.
  #
  #   echo 'psk_BoatWifi=the-password' > /etc/wpa_supplicant/psk.env
  networking.wireless = {
    enable = true;
    secretsFile = "/etc/wpa_supplicant/psk.env";
    networks."BoatWifi".psk = "@psk_BoatWifi@";
  };

  # No 4-core 1.5 GHz helm box here: keep the heavy autopilot/charting services
  # off and run the box as a wifi camera sensor only.
  services.navigation.pypilot.enable = lib.mkForce false;
  services.navigation.opencpn.enable = false;
  services.navigation.desktop.enable = false;
}
