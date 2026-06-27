# SIM7600X 4G & LTE Cat-1 HAT (Waveshare) — cellular uplink + GNSS.
#
# Interfaces brought up here:
#  - USB   : the HAT's micro-USB "USB" port enumerates a SIMCOM composite device
#            (VID 1e0e). qmi_wwan exposes cdc-wdm0 + wwan0 (data); the `option`
#            driver exposes ttyUSB0 diag, ttyUSB1 NMEA GPS, ttyUSB2 AT, ttyUSB3
#            PPP. This USB path (not the header UART) is the high-throughput one.
#  - UART0 : the HAT also wires its serial to GPIO14/15 (single AT channel); the
#            header path is claimed for conflict detection even when USB is used.
#  - Power : the HAT auto-powers when the on-board PWR<->3V3 jumper is fitted, so
#            no GPIO is driven here (see doc/sim7600x.fr.md for manual PWRKEY).
#
# ModemManager owns the modem (works standalone, alongside the hosts' wireless
# wpa_supplicant — different interfaces, no conflict). The data link rides the
# system DHCP client on wwan0 once the bearer is up. Pinout/USB layout follow the
# Waveshare wiki; validated on the bench (level 3).
#
# TODO: package for nixpkgs the SIMCom helpers some setups prefer (see
# doc/sim7600x.fr.md):
#  - pkgs/simcom-wwan : the vendor out-of-tree driver (alternative to qmi_wwan
#    that SIMCom recommends for the SIM7600 in some kernels).
#  - a thin `sim7600x` CLI wrapping the common mmcli/qmicli incantations.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  hat = cfg.sim7600xHat;
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    optionalString
    types
    ;

  # Wait for ModemManager to enumerate the modem, then connect the bearer; the
  # APN is added only when set, otherwise ModemManager auto-detects it.
  connectScript = pkgs.writeShellScript "sim7600x-connect" ''
    mmcli=${pkgs.modemmanager}/bin/mmcli

    # cdc-wdm0/wwan0 appear a few seconds after USB enumeration; poll briefly.
    for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
      "$mmcli" -L | ${pkgs.gnugrep}/bin/grep -q '/Modem/' && break
      ${pkgs.coreutils}/bin/sleep 2
    done

    exec "$mmcli" -m any --simple-connect="${
      optionalString (hat.apn != "") "apn=${hat.apn},"
    }ip-type=ipv4"
  '';

  # NMEA + raw GNSS exposed through ModemManager's location API; read it with
  # `mmcli -m any --location-get` or off the ttyUSB1 NMEA port.
  gpsScript = pkgs.writeShellScript "sim7600x-gps" ''
    exec ${pkgs.modemmanager}/bin/mmcli -m any \
      --location-enable-gps-nmea --location-enable-gps-raw
  '';
in
{
  options.services.navigation.sim7600xHat = {
    connection.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Connect the cellular data bearer at boot via ModemManager (wwan0).";
    };

    apn = mkOption {
      type = types.str;
      default = "";
      example = "internet";
      description = "Carrier APN; empty lets ModemManager auto-detect it.";
    };

    gps.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the modem's GNSS receiver (NMEA + raw) through ModemManager.";
    };
  };

  config = mkIf cfg.hardware.hats.enableSim7600x (mkMerge [
    {

      # Header UART (GPIO14/15) is wired by the HAT even when the USB port is the
      # active link; claim it so a second UART HAT is refused.
      services.navigation.hardware.gpioClaims = [
        {
          owner = "sim7600x-hat";
          pins = [
            14
            15
          ];
        }
      ];

      # SIMCOM composite USB: `option` for the ttyUSB AT/PPP/NMEA channels,
      # qmi_wwan + cdc_wdm for the cdc-wdm0/wwan0 QMI data interface.
      boot.kernelModules = [
        "option"
        "usb_wwan"
        "cdc_wdm"
        "qmi_wwan"
      ];

      # ModemManager drives the modem; standalone (no NetworkManager) so it sits
      # beside the hosts' wpa_supplicant without fighting over wlan0.
      networking.modemmanager.enable = true;

      # Stable names for the AT and NMEA channels (interface numbers are fixed in
      # the SIMCOM QMI composition: if01 = NMEA, if02 = AT).
      services.udev.extraRules = ''
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1e0e", ENV{ID_USB_INTERFACE_NUM}=="01", SYMLINK+="ttySIM_gps"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1e0e", ENV{ID_USB_INTERFACE_NUM}=="02", SYMLINK+="ttySIM_at"
      '';

      # mmcli (modem) + qmicli/mbimcli (QMI/MBIM) for data, usb-modeswitch for
      # the storage->modem flip, minicom for raw AT debugging on ttySIM_at.
      environment.systemPackages = [
        pkgs.modemmanager
        pkgs.libqmi
        pkgs.libmbim
        pkgs.usb-modeswitch
        pkgs.minicom
      ];
    }

    (mkIf hat.connection.enable {

      # Bring the bearer up after ModemManager; the system DHCP client then
      # configures wwan0 (see doc for the QMI raw-ip note if DHCP stays silent).
      systemd.services.sim7600x-connect = {
        description = "Connect SIM7600X cellular data bearer (wwan0)";
        after = [ "ModemManager.service" ];
        wants = [ "ModemManager.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = connectScript;
        };
      };
    })

    (mkIf hat.gps.enable {

      # Turn the GNSS receiver on once the modem is ready.
      systemd.services.sim7600x-gps = {
        description = "Enable SIM7600X GNSS (NMEA + raw)";
        after = [ "ModemManager.service" ];
        wants = [ "ModemManager.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = gpsScript;
        };
      };
    })
  ]);
}
