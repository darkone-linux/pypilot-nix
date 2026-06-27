# network.nix — on-board LAN: gateway (DHCP/DNS/NAT) and WiFi hotspot.
#
# One module, two self-gating roles over a single fixed class-B LAN
# (172.16.0.0/16, box at 172.16.0.1):
#
#   - gateway: set `upstreamInterface` (the internet uplink). Every *other*
#     interface joins a `br-lan` bridge (systemd-networkd), dnsmasq serves DHCP
#     and DNS on it, and the uplink is NATed. There can be only one gateway per
#     LAN.
#   - hotspot: `hotspot.enable` brings up hostapd. With a gateway it is bridged
#     into br-lan (shared DHCP pool, wired + WiFi on one subnet); standalone it
#     owns the AP interface, serves DHCP there and NATs the default uplink.
#
# `fixedIps` (MAC -> IP) pins addresses inside the reserved 172.16.0.0/24; the
# rest of the /16 is the DHCP pool. The pure helpers/validation live in
# `navLib.network` (lib/network.nix), unit-tested in isolation.

{
  config,
  lib,
  navLib,
  ...
}:

let
  cfg = config.services.navigation.network;
  hs = cfg.hotspot;

  inherit (lib)
    mkIf
    mkMerge
    mkEnableOption
    mkOption
    optionalAttrs
    types
    ;

  # upstream set => this host routes/NATs the LAN (gateway role).
  gatewayMode = cfg.upstreamInterface != "";

  # Box address and the interface the DHCP/DNS server binds to: the bridge when
  # routing, else the lone AP interface.
  gateway = "172.16.0.1";
  lanInterface = if gatewayMode then "br-lan" else hs.interface;

  # fixedIps as dnsmasq reservations (MAC,IP).
  dhcpHosts = lib.mapAttrsToList (mac: ip: "${mac},${ip}") cfg.fixedIps;
in
{
  options.services.navigation.network = {
    upstreamInterface = mkOption {
      type = types.str;
      default = "";
      example = "eth0";
      description = ''
        Internet/upstream interface. Setting it makes this host the LAN gateway:
        all other interfaces are bridged into the local network and NATed out
        through this one. Empty: no gateway (hotspot may still run standalone).
      '';
    };

    fixedIps = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        "de:ad:be:ef:00:11" = "172.16.0.10";
      };
      description = ''
        Static DHCP reservations, MAC -> IP. Each IP must sit in the reserved
        range 172.16.0.2-172.16.0.254; the rest of 172.16.0.0/16 is the DHCP
        pool. Served by the gateway and/or the hotspot.
      '';
    };

    hotspot = {
      enable = mkEnableOption "the on-board WiFi access point (hostapd)";

      interface = mkOption {
        type = types.str;
        default = "wlan0";
        description = "Wireless interface serving the access point.";
      };

      ssid = mkOption {
        type = types.str;
        default = navLib.network.defaultSsid config.networking.hostName;
        defaultText = lib.literalExpression ''"''${Hostname}OnBoardWifi"'';
        description = "Broadcast network name; defaults to the capitalised host name.";
      };

      password = mkOption {
        type = types.str;
        default = "ILikePyPilot";
        description = ''
          WPA2 passphrase (min 8 chars). First-boot convenience — change it
          before going to sea. Stored world-readable in the Nix store.
        '';
      };

      channel = mkOption {
        type = types.int;
        default = 6;
        description = "2.4 GHz channel.";
      };

      countryCode = mkOption {
        type = types.str;
        default = "FR";
        description = ''
          Regulatory domain (ISO 3166-1). Mandatory for the AP to come up: under
          the default world domain "00" the 2.4 GHz channels are no-initiating-
          radiation and hostapd fails with "Unable to setup interface".
        '';
      };
    };
  };

  config = mkMerge [

    # Validation: applies regardless of the active role.
    {
      assertions =
        map (msg: {
          assertion = false;
          message = msg;
        }) (navLib.network.fixedIpsErrors cfg.fixedIps)
        ++ [
          {
            assertion = cfg.fixedIps == { } || gatewayMode || hs.enable;
            message = "services.navigation.network.fixedIps needs a DHCP server: set upstreamInterface (gateway) or enable the hotspot.";
          }
          {
            assertion = !(gatewayMode && cfg.upstreamInterface == hs.interface);
            message = "services.navigation.network: upstreamInterface and hotspot.interface must differ.";
          }
        ];
    }

    # Gateway: bridge every non-upstream interface, address the bridge, NAT out.
    (mkIf gatewayMode {

      # networkd is the sole backend here: keep dhcpcd off the LAN/bridge.
      networking.useNetworkd = true;

      systemd.network = {
        enable = true;

        netdevs."20-br-lan".netdevConfig = {
          Name = "br-lan";
          Kind = "bridge";
        };

        networks = {

          # Uplink: DHCP client toward the internet.
          "10-upstream" = {
            matchConfig.Name = cfg.upstreamInterface;
            networkConfig.DHCP = "ipv4";
          };

          # Every other wired interface joins the LAN bridge (the AP is added by
          # hostapd; wlan/loopback are excluded by Type=ether).
          "30-lan-members" = {
            matchConfig = {
              Type = "ether";
              Name = "!${cfg.upstreamInterface} !br-lan *";
            };
            networkConfig.Bridge = "br-lan";
          };

          # The bridge carries the fixed gateway address (up without carrier so
          # DHCP serves even before a client is plugged in).
          "40-br-lan" = {
            matchConfig.Name = "br-lan";
            networkConfig = {
              Address = "${gateway}/16";
              ConfigureWithoutCarrier = true;
            };
          };
        };
      };

      networking.nat = {
        enable = true;
        externalInterface = cfg.upstreamInterface;
        internalInterfaces = [ "br-lan" ];
      };

      # Keep NetworkManager (cellular module) off the bridge and AP.
      networking.networkmanager.unmanaged = mkIf config.networking.networkmanager.enable [
        "interface-name:br-lan"
        "interface-name:${hs.interface}"
      ];
    })

    # Hotspot: hostapd on the AP interface.
    (mkIf hs.enable {
      services.hostapd = {
        enable = true;
        radios.${hs.interface} = {
          band = "2g";
          inherit (hs) channel countryCode;
          networks.${hs.interface} = {
            inherit (hs) ssid;
            authentication = {
              mode = "wpa2-sha256";
              wpaPassword = hs.password;
            };

            # With a gateway, hand the radio to br-lan (one shared DHCP pool).
            settings = optionalAttrs gatewayMode { bridge = "br-lan"; };
          };
        };
      };

      networking = mkMerge [

        # hostapd owns the radio; the wpa_supplicant client must stay off.
        { wireless.enable = lib.mkForce false; }

        # Standalone (no gateway): the AP interface carries the address itself
        # and NATs the default uplink — eth0 stays the host's own link.
        (mkIf (!gatewayMode) {
          interfaces.${hs.interface}.ipv4.addresses = [
            {
              address = gateway;
              prefixLength = 16;
            }
          ];
          nat = {
            enable = true;
            internalInterfaces = [ hs.interface ];
          };
          networkmanager.unmanaged = mkIf config.networking.networkmanager.enable [
            "interface-name:${hs.interface}"
          ];
        })
      ];
    })

    # DHCP + DNS for the LAN, bound to the bridge or the AP interface.
    (mkIf (gatewayMode || hs.enable) {
      services.dnsmasq = {
        enable = true;
        settings = {
          interface = lanInterface;
          bind-interfaces = true;
          dhcp-range = [ "172.16.1.1,172.16.255.254,255.255.0.0,24h" ];
          dhcp-option = [ "option:router,${gateway}" ];
          dhcp-host = dhcpHosts;
        };
      };
    })
  ];
}
