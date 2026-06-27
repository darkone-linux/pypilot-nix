# Kitronik 5038 Air Quality Control HAT — environmental sensing + I/O.
#
# Buses exercised:
#  - I2C-1  : BME688 air-quality/environment sensor + 128x64 OLED display.
#  - UART0  : on-board RP2040 co-processor (ZIP LEDs, ADC0-2, RTC) over serial0.
#  - GPIO   : buzzer (26), two 1A outputs (13/19), servo (6), breakouts (22-24).
#
# The Pi speaks I2C to the BME688/OLED and serial0 to the RP2040, which owns the
# analogue inputs, the addressable LEDs and the clock. Kitronik's Python library
# drives both; it is not in nixpkgs, so we ship the protocol tooling (pyserial +
# smbus2) and let it be `pip install`-ed in a venv. Pinout follows the HAT
# datasheet; validated on the bench (level 3).
#
# TODO: package for nixpkgs so no venv/pip is needed (see doc/aqc5038.fr.md):
#  - pkgs/kitronik-air-quality-control-hat.nix : the vendor driver (MIT). Deps:
#    RPi.GPIO, pyserial, pillow and `smbus` (it imports `smbus`, not `smbus2` —
#    patch to smbus2 or wire smbus-cffi).
#  - pkgs/python3Packages/luma-oled : SSD1306 lib (luma-core is in nixpkgs,
#    luma-oled is not), an alternative to the driver's built-in OLED code.
#  - then drop pythonEnv here and expose the driver directly.

{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  hat = cfg.aqc5038Hat;
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    types
    ;

  # The vendor config.txt option exists only on the nixos-raspberrypi base
  # (Pi hosts), not on the plain-nixpkgs lab VM. Emit the bus enablement only
  # where it is declared, so the module stays evaluable everywhere.
  hasConfigTxt = options.hardware ? raspberry-pi;

  # The two wire protocols the HAT speaks: serial0 to the RP2040, I2C to the
  # BME688 and OLED. Matches what Kitronik's library imports under the hood.
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pyserial
    ps.smbus2
  ]);
in
{
  options.services.navigation.aqc5038Hat = {
    pythonTooling.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install python3 with pyserial + smbus2 to talk to the RP2040 and the I2C sensor/OLED.";
    };
  };

  config = mkIf cfg.hardware.hats.enableAqc5038 (mkMerge [
    {

      # Pins driven by the HAT: I2C-1 (2/3), serial0/RP2040 (14/15), buzzer (26),
      # 1A outputs (13/19), servo (6) and the 22-24 breakouts.
      services.navigation.hardware.gpioClaims = [
        {
          owner = "aqc5038-hat";
          pins = [
            2
            3
            6
            13
            14
            15
            19
            22
            23
            24
            26
          ];
        }
      ];

      # BME688 and the OLED share I2C-1; reached from userspace via /dev/i2c-1.
      hardware.i2c.enable = true;

      # serial0 carries data to the RP2040, not a login console.
      systemd.services."serial-getty@ttyAMA0".enable = false;

      # i2c-tools for bench bring-up (i2cdetect: BME688 at 0x76/0x77, OLED 0x3c).
      environment.systemPackages = [ pkgs.i2c-tools ];
    }

    (mkIf hat.pythonTooling.enable {
      environment.systemPackages = [ pythonEnv ];
    })

    # Bus enablement via the vendor firmware config.txt (nixos-raspberrypi):
    # these dtparams/overlays actually apply (vendor DTBs ship __symbols__).
    (optionalAttrs hasConfigTxt {
      hardware.raspberry-pi.config.all = {
        base-dt-params = {

          # I2C-1 -> /dev/i2c-1, the BME688 sensor and the OLED display.
          i2c_arm = {
            enable = true;
            value = "on";
          };

          # serial0 -> the RP2040 co-processor link.
          enable_uart = {
            enable = true;
            value = "on";
          };
        };

        # Pin serial0 to the PL011 (ttyAMA0): move Bluetooth off the UART so the
        # RP2040 gets a stable, full-speed port instead of the mini-UART.
        dt-overlays.disable-bt = {
          enable = true;
          params = { };
        };
      };
    })
  ]);
}
