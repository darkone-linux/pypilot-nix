# hotspot.nix — optional on-board WiFi access point.
#
# Declarative equivalent of OpenPlotter's "openplotter-ap": the boat box serves
# its own WiFi so phones/tablets reach OpenCPN, Signal K and the instruments
# without any shore network. hostapd runs the AP, dnsmasq hands out DHCP, and
# the uplink (cellular/ethernet) is NATed to the clients. Off by default.
#
# Note: the AP interface gets a static IP here; when NetworkManager is active
# (cellular module) it is marked unmanaged so the two do not fight over it.

{
  config,
  lib,
  ...
}:

let
  cfg = config.services.navigation.hotspot;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  # Derive the addressing from the /24 prefix: box is .1, clients .10–.100.
  gateway = "${cfg.subnet}.1";
in
{
  options.services.navigation.hotspot = {
    enable = mkEnableOption "the on-board WiFi access point (hostapd + dnsmasq)";

    interface = mkOption {
      type = types.str;
      default = "wlan0";
      description = "Wireless interface serving the access point.";
    };

    ssid = mkOption {
      type = types.str;
      default = "pypilot";
      description = "Broadcast network name.";
    };

    passphrase = mkOption {
      type = types.str;
      default = "pypilotnix";
      description = ''
        WPA2 passphrase (min 8 chars). First-boot convenience — change it before
        going to sea. Stored world-readable in the Nix store.
      '';
    };

    channel = mkOption {
      type = types.int;
      default = 6;
      description = "2.4 GHz channel.";
    };

    subnet = mkOption {
      type = types.str;
      default = "10.10.0";
      description = "/24 prefix for the AP network (box takes <prefix>.1).";
    };
  };

  config = mkIf cfg.enable {

    services.hostapd = {
      enable = true;
      radios.${cfg.interface} = {
        band = "2g";
        inherit (cfg) channel;
        networks.${cfg.interface} = {
          inherit (cfg) ssid;
          authentication = {
            mode = "wpa2-sha256";
            wpaPassword = cfg.passphrase;
          };
        };
      };
    };

    networking = {

      # Static IP for the AP; hostapd brings the radio up, networkd the address.
      interfaces.${cfg.interface}.ipv4.addresses = [
        {
          address = gateway;
          prefixLength = 24;
        }
      ];

      # Keep NetworkManager (cellular module) off the AP interface.
      networkmanager.unmanaged = mkIf config.networking.networkmanager.enable [
        "interface-name:${cfg.interface}"
      ];

      # Share the uplink (cellular/ethernet) with the AP clients.
      nat = {
        enable = true;
        internalInterfaces = [ cfg.interface ];
      };

      # hostapd manages the radio; the wpa_supplicant client must stay off.
      wireless.enable = lib.mkForce false;
    };

    # DHCP + DNS for the clients, bound to the AP interface only.
    services.dnsmasq = {
      enable = true;
      settings = {
        inherit (cfg) interface;
        bind-interfaces = true;
        dhcp-range = [ "${cfg.subnet}.10,${cfg.subnet}.100,24h" ];
        dhcp-option = [ "option:router,${gateway}" ];
      };
    };
  };
}
