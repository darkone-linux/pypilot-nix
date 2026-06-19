# MacArthur HAT — multiplexed marine I/O for the navigation stack.
#
# Interfaces brought up here:
#  - I2C-1 : 9DOF IMU, DS3231 RTC, SC16IS752 dual UART, STEMMA QT / Qwiic.
#  - UART0 : PL011 on GPIO14/15, wired to the on-board AIS receiver (ttyAMA0).
#  - SPI0  : MCP2515 CAN controller for NMEA2000.
#
# The complex device overlays (MCP2515, SC16IS752, DS3231, GPIO shutdown) depend
# on the firmware boot mechanism and exact pinout; their kernel modules are
# loaded here and the matching `dtoverlay=` lines documented for the host
# firmware config. Pin/oscillator defaults follow common HAT conventions and are
# validated on the bench (level 3).

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  hat = cfg.macarthurHat;
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
    ;
in
{
  options.services.navigation.macarthurHat = {
    nmea2000 = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Bring up the MCP2515 CAN controller as NMEA2000 (can0).";
      };
      bitrate = mkOption {
        type = types.ints.positive;
        default = 250000;
        description = "CAN bitrate; NMEA2000 mandates 250 kbit/s.";
      };
    };

    extraSerial.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Load the SC16IS752 driver exposing the HAT's NMEA0183 UARTs (ttySC0/ttySC1).";
    };

    rtc.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Load the DS3231 RTC driver for offline timekeeping.";
    };

    powerManagement.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Honour the HAT's GPIO shutdown request for clean power-down.";
    };
  };

  config = mkIf (cfg.hardware == "macarthur-hat") (mkMerge [

    {

      # IMU, RTC and the SC16IS752 UART expander all share I2C-1.
      hardware.i2c.enable = true;

      hardware.deviceTree = {
        enable = true;

        # Enable the i2c1 and spi0 controllers (shipped disabled in the base
        # DT); equivalent to dtparam=i2c_arm=on,spi=on.
        overlays = [
          {
            name = "macarthur-hat-i2c1";
            dtsText = ''
              /dts-v1/;
              /plugin/;
              / {
                compatible = "brcm,bcm2835";
                fragment@0 {
                  target = <&i2c1>;
                  __overlay__ { status = "okay"; };
                };
              };
            '';
          }
          {
            name = "macarthur-hat-spi0";
            dtsText = ''
              /dts-v1/;
              /plugin/;
              / {
                compatible = "brcm,bcm2835";
                fragment@0 {
                  target = <&spi0>;
                  __overlay__ { status = "okay"; };
                };
              };
            '';
          }
        ];
      };

      # The PL011 (ttyAMA0) feeds the AIS receiver, so it must carry data, not a
      # login console. Freeing it from Bluetooth needs `dtoverlay=disable-bt`
      # plus dropping `console=serial0` from the firmware cmdline (host config).
      systemd.services."serial-getty@ttyAMA0".enable = false;

      environment.systemPackages = [
        pkgs.i2c-tools
        pkgs.can-utils
      ];
    }

    (mkIf hat.extraSerial.enable {

      # SC16IS752 dual UART over I2C → /dev/ttySC0, /dev/ttySC1.
      # Firmware overlay: dtoverlay=sc16is752-i2c,int_pin=24,addr=0x4d
      boot.kernelModules = [ "sc16is7xx" ];
    })

    (mkIf hat.rtc.enable {

      # DS3231 battery-backed clock at I2C 0x68; keeps time without network.
      # Firmware overlay: dtoverlay=i2c-rtc,ds3231
      boot.kernelModules = [ "rtc-ds3231" ];
    })

    (mkIf hat.nmea2000.enable {

      # MCP2515 CAN controller on SPI0.0 → NMEA2000.
      # Firmware overlay: dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25
      boot.kernelModules = [
        "can"
        "can-raw"
        "mcp251x"
      ];

      # can0 only appears once the overlay binds the controller; bring the link
      # up at the NMEA2000 bitrate when the kernel registers it.
      systemd.services.macarthur-can0 = {
        description = "Bring up MacArthur HAT NMEA2000 link (can0)";
        bindsTo = [ "sys-subsystem-net-devices-can0.device" ];
        after = [ "sys-subsystem-net-devices-can0.device" ];
        wantedBy = [ "sys-subsystem-net-devices-can0.device" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.iproute2}/bin/ip link set can0 up type can bitrate ${toString hat.nmea2000.bitrate}";
          ExecStop = "${pkgs.iproute2}/bin/ip link set can0 down";
        };
      };
    })

    (mkIf hat.powerManagement.enable {

      # The HAT requests OS shutdown by pulling a GPIO; the firmware overlay
      # `dtoverlay=gpio-shutdown,gpio_pin=26` (confirm pin) emits KEY_POWER.
      # Make logind act on it explicitly.
      services.logind.settings.Login.HandlePowerKey = "poweroff";
    })
  ]);
}
