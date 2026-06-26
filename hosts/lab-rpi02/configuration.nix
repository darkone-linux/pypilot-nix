# lab-rpi02 — Raspberry Pi Zero 2 W lab host, wifi + Camera Module 3 Wide.
#
# Headless, RAM-constrained (512 MB) sensor node: no chartplotter desktop, no
# autopilot HAT. Reaches the boat network over the onboard wifi and streams the
# CSI camera through libcamera.
#
# Wifi PSK secrecy: held in sops (secrets/wifi.yaml, committed encrypted),
# decrypted at activation and rendered into /run/secrets — never in the Nix
# store. The decryption key is an age key the operator drops on the SD boot
# partition before first boot (no peripheral, so it must be there to connect).

{ config, lib, ... }:

let
  # The SSID is broadcast in clear by the access point, so it is not a secret:
  # keep it here and edit it per site. Only the PSK lives in sops.
  wifiSsid = "BoatWifi";

  # sops wiring activates only once the encrypted secrets file is committed.
  # Until then (fresh clone, CI) the host still evaluates — without wifi — so it
  # never breaks `nix flake check`.
  sopsFile = ../../secrets/wifi.yaml;
  hasSecrets = builtins.pathExists sopsFile;
in
{
  imports = [ ../rpi.nix ];

  config = lib.mkMerge [
    {
      networking.hostName = "lab-rpi02";

      # Camera Module 3 Wide on the CSI connector (no header GPIO, see module).
      services.navigation.hardware.modules.enableCamera3Wide = true;

      # Stream it over the wifi: RTSP (rtsp://lab-rpi02.local:8554/cam) and
      # WebRTC (http://lab-rpi02.local:8889/cam) for any boat-network machine.
      services.navigation.hardware.modules.camera3Wide.streaming = {
        enable = true;
        openFirewall = true;
      };

      # Onboard Cypress wifi: brcmfmac firmware ships with linux-firmware, not
      # the vendor base, so pull it in explicitly.
      hardware.enableRedistributableFirmware = true;

      # No 4-core 1.5 GHz helm box here: keep the heavy autopilot/charting
      # services off and run the box as a wifi camera sensor only.
      services.navigation.pypilot.enable = lib.mkForce false;
      services.navigation.opencpn.enable = false;
      services.navigation.desktop.enable = false;
    }

    (lib.mkIf hasSecrets {
      sops = {
        defaultSopsFile = sopsFile;

        # Headless first boot: the only identity is the age key the operator
        # copies onto the FAT boot partition. Disable the SSH-host-key path
        # (that key is generated too late to decrypt on the very first boot).
        age.keyFile = "/boot/firmware/secrets/age.txt";
        age.sshKeyPaths = [ ];
        gnupg.sshKeyPaths = [ ];

        secrets.wifi_psk = { };

        # wpa_supplicant reads `psk_wifi=…` as an external password (the `ext:`
        # ref below). Rendered with the decrypted PSK at activation, mode 0400.
        templates."wpa-supplicant.psk".content = ''
          psk_wifi=${config.sops.placeholder.wifi_psk}
        '';
      };

      # Note: the age key lives on the FAT boot partition. sops-nix already
      # gates secret installation on that mount (RequiresMountsFor on
      # age.keyFile / activation runs post-mount), so no extra ordering here —
      # but confirm first-boot decryption on the bench (level 3).

      # Auto-connect over wpa_supplicant (lighter than NetworkManager on the
      # Zero 2). The PSK comes from the sops template; only the `ext:` reference
      # and the SSID end up in the store.
      networking.wireless = {
        enable = true;
        secretsFile = config.sops.templates."wpa-supplicant.psk".path;
        networks.${wifiSsid}.pskRaw = "ext:psk_wifi";
      };
    })

    (lib.mkIf (!hasSecrets) {

      # Loud at build: a headless box with no wifi is unreachable. Commit the
      # encrypted secrets/wifi.yaml (see secrets/README.md) to wire it.
      warnings = [
        "lab-rpi02: secrets/wifi.yaml is missing, wifi is OFF — the headless box will be unreachable. See secrets/README.md."
      ];
    })
  ];
}
