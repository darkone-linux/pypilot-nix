# cellular.nix — optional 4G/LTE USB modem connectivity.
#
# Declarative equivalent of OpenPlotter's mobile-data setup: NetworkManager
# drives the WWAN through ModemManager (mmcli), usb-modeswitch flips dongles out
# of their fake CD-ROM mode, ppp covers the dial-up modems. Off by default.
#
# Note: enabling this switches the host's networking to NetworkManager (it
# replaces the default dhcpcd). Wire it on a host only when a modem is fitted.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation.cellular;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.services.navigation.cellular = {
    enable = mkEnableOption "4G/LTE USB modem connectivity (NetworkManager + ModemManager)";

    apn = mkOption {
      type = types.str;
      default = "";
      example = "internet";
      description = "Carrier APN for the auto-created GSM connection (empty: configure with nmcli).";
    };

    autoconnect = mkOption {
      type = types.bool;
      default = true;
      description = "Bring the modem connection up automatically when present.";
    };
  };

  config = mkIf cfg.enable {

    # NetworkManager owns the WWAN; it auto-enables ModemManager
    # (networking.modemmanager.enable defaults true under NetworkManager).
    networking.networkmanager = {
      enable = true;

      # Seed a GSM connection from the APN; left for nmcli when unset.
      ensureProfiles.profiles = mkIf (cfg.apn != "") {
        cellular = {
          connection = {
            id = "cellular";
            type = "gsm";
            inherit (cfg) autoconnect;
          };
          gsm = {
            inherit (cfg) apn;
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };

    # mmcli (diagnostics), dongle mode switch and dial-up backend.
    environment.systemPackages = [
      pkgs.modemmanager
      pkgs.usb-modeswitch
      pkgs.ppp
    ];

    # udev rules that flip multi-mode dongles from storage to modem.
    services.udev.packages = [ pkgs.usb-modeswitch-data ];
  };
}
