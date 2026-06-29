# lab-rpi02 — Raspberry Pi Zero 2 W lab host, wifi + Camera Module 3 Wide.
#
# Headless, RAM-constrained (512 MB) sensor node: no chartplotter desktop, no
# autopilot HAT. Reaches the boat network over the onboard wifi and streams the
# CSI camera through libcamera.
#
# Wifi PSK secrecy: held in sops (secrets/<host>.yaml, committed encrypted),
# decrypted at activation and rendered into /run/secrets — never in the Nix
# store. The decryption key is the host's age key, dropped on the SD boot
# partition before first boot (no peripheral, so it must be there to connect).
# Provision both with `just init lab-rpi02`.

{ config, lib, ... }:

let
  hostName = "lab-rpi02";

  # The SSID is broadcast in clear by the access point, so it is not a secret:
  # keep it here and edit it per site. Only the PSK lives in sops.
  wifiSsid = "ARTHUR";

  # Per-host encrypted secret; sops wiring activates only once it is committed.
  # Until then (fresh clone, CI) the host still evaluates — so it never breaks
  # `nix flake check`.
  sopsFile = ../../secrets/${hostName}.yaml;
  hasSecrets = builtins.pathExists sopsFile;
in
{
  config = lib.mkMerge [
    {
      networking.hostName = hostName;

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

      # Onboard wifi is this headless box's only link. Enable the supplicant
      # unconditionally so it expresses the intent (read by `just init`); the
      # network and PSK below are wired once the encrypted secret exists.
      networking.wireless.enable = true;

      # No 4-core 1.5 GHz helm box here: keep the heavy autopilot/charting
      # services off and run the box as a wifi camera sensor only.
      services.navigation.pypilot.enable = lib.mkForce false;
      services.navigation.opencpn.enable = false;
      services.navigation.desktop.enable = false;
    }

    (lib.mkIf hasSecrets {
      sops = {
        defaultSopsFile = sopsFile;

        # Headless first boot: the only identity is the host age key the operator
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
      networking.wireless = {
        secretsFile = config.sops.templates."wpa-supplicant.psk".path;
        networks.${wifiSsid}.pskRaw = "ext:psk_wifi";
      };
    })

    (lib.mkIf (!hasSecrets) {

      # Loud at build: wifi is on but has no PSK, so this headless box stays
      # unreachable. Run `just init lab-rpi02` to mint the key and capture it.
      warnings = [
        "lab-rpi02: wifi enabled but no PSK (secrets/lab-rpi02.yaml missing) — run `just init lab-rpi02`; the headless box stays unreachable."
      ];
    })
  ];
}
