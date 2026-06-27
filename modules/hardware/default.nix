# Hardware HAT and module selector.
#
# Declares services.navigation.hardware and imports the per-device modules. Each
# HAT/module is an independent boolean: zero, one or several can be enabled at
# once. Conflicts (two devices wanting the same BCM GPIO) are caught by
# assertions, fed by the internal gpioClaims registry each module appends to.

{
  config,
  lib,
  navLib,
  ...
}:

let
  cfg = config.services.navigation;
  inherit (lib) mkOption types;

  conflictMessage = navLib.hardware.gpioConflictMessage cfg.hardware.gpioClaims;
in
{
  imports = [
    ./pypilot-hat.nix
    ./macarthur-hat.nix
    ./sim7600x-hat.nix
    ./xpt2046-hat.nix
    ./aqc5038-hat.nix
    ./camera3-wide.nix
  ];

  options.services.navigation.hardware = {
    hats = {
      enablePypilot = mkOption {
        type = types.bool;
        default = false;
        description = "Fit the Pypilot HAT (IMU + control head for the autopilot).";
      };

      enableMacArthur = mkOption {
        type = types.bool;
        default = false;
        description = "Fit the MacArthur HAT (NMEA2000 CAN, extra UARTs, RTC).";
      };

      enableSim7600x = mkOption {
        type = types.bool;
        default = false;
        description = "Fit the SIM7600X 4G/LTE HAT (cellular uplink + GNSS via ModemManager).";
      };

      enableXpt2046 = mkOption {
        type = types.bool;
        default = false;
        description = "Fit the XPT2046 touchscreen HAT (SPI ILI9486 LCD + resistive touch).";
      };

      enableAqc5038 = mkOption {
        type = types.bool;
        default = false;
        description = "Fit the Kitronik 5038 Air Quality Control HAT (BME688, OLED, RP2040 I/O).";
      };
    };

    modules = {
      enableCamera3Wide = mkOption {
        type = types.bool;
        default = false;
        description = "Fit the Raspberry Pi Camera Module 3 Wide (IMX708 on CSI).";
      };
    };

    # Internal: each enabled device appends the BCM GPIOs it drives, so the
    # selector can refuse incompatible combinations through assertions.
    gpioClaims = mkOption {
      internal = true;
      type = types.listOf (
        types.submodule {
          options = {
            owner = mkOption {
              type = types.str;
              description = "Device claiming the pins (used in conflict messages).";
            };
            pins = mkOption {
              type = types.listOf types.int;
              default = [ ];
              description = "BCM GPIO numbers the device drives.";
            };
          };
        }
      );
      default = [ ];
      description = "Internal registry of BCM GPIOs claimed by enabled HATs/modules.";
    };
  };

  config = {

    # Single assertion: incompatible devices share BCM GPIOs and cannot coexist.
    assertions = [
      {
        assertion = conflictMessage == null;
        message = lib.optionalString (conflictMessage != null) conflictMessage;
      }
    ];
  };
}
