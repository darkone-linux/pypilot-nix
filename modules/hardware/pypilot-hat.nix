# Pypilot HAT — IMU and control head for the pypilot autopilot.
#
# Buses exercised:
#  - I2C-1 : ICM20948 IMU, read from userspace by RTIMULib (raw /dev/i2c-1).
#  - SPI0  : JLX12864 LCD (ST7565) driven by pypilot's hat/ugfx via spidev.
#  - UART0 : PL011 (ttyAMA0) → arduino_servo motor controller at 38400 bd.
#  - GPIO  : keypad, 433 MHz RF receiver, buzzer.
#
# Buses are enabled through the vendor firmware config.txt
# (hardware.raspberry-pi.config, nixos-raspberrypi) plus access groups; exact
# pinout is validated on the bench (level 3).

{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  inherit (lib)
    mkIf
    mkMerge
    optionalAttrs
    ;

  # The vendor config.txt option exists only on the nixos-raspberrypi base
  # (Pi hosts), not on the plain-nixpkgs lab VM. Emit the bus enablement only
  # where it is declared, so the module stays evaluable everywhere.
  hasConfigTxt = options.hardware ? raspberry-pi;
in
{
  config = mkIf cfg.hardware.hats.enablePypilot (mkMerge [
    {

      # Pins driven by the HAT: I2C-1 (2/3), SPI0 (7-11), UART0 (14/15). Keypad,
      # 433 MHz RF and buzzer GPIOs add to this once the bench pinout is fixed.
      services.navigation.hardware.gpioClaims = [
        {
          owner = "pypilot-hat";
          pins = [
            2
            3
            7
            8
            9
            10
            11
            14
            15
          ];
        }
      ];

      # ICM20948 sits on I2C-1; RTIMULib reaches it through /dev/i2c-1, so only
      # bus access (i2c-dev + i2c group) is needed, no kernel IMU driver.
      hardware.i2c.enable = true;

      # spidev exposes the LCD bus to pypilot's display code; the vendor
      # firmware auto-loads it once SPI is on, but request it explicitly.
      boot.kernelModules = [ "spidev" ];

      # No login console on the motor-controller UART.
      systemd.services."serial-getty@ttyAMA0".enable = false;

      # GPIO (keypad/RF/buzzer) and spidev access; plain nixpkgs ships no rpi
      # udev rules, so expose the device nodes to dedicated groups.
      users.groups = {
        gpio = { };
        spi = { };
      };

      services.udev.extraRules = ''
        SUBSYSTEM=="bcm2835-gpiomem", GROUP="gpio", MODE="0660"
        KERNEL=="gpiochip[0-9]*", GROUP="gpio", MODE="0660"
        KERNEL=="spidev[0-9]*.[0-9]*", GROUP="spi", MODE="0660"

        # Stable name for the motor controller, matching OpenPlotter's
        # convention; fe201000.serial is the BCM2711 (Pi 4) PL011 (Pi 5 differs).
        KERNEL=="ttyAMA[0-9]*", KERNELS=="fe201000.serial:0.0", SYMLINK+="ttyOP_pilot", GROUP="dialout", MODE="0660"
      '';

      # i2c-tools for bench bring-up (i2cdetect on the IMU).
      environment.systemPackages = [ pkgs.i2c-tools ];
    }

    # Bus enablement via the vendor firmware config.txt (nixos-raspberrypi):
    # these dtparams/overlays actually apply (vendor DTBs ship __symbols__),
    # unlike the generic image. Equivalent to RPi OS dtparam=spi=on,i2c_arm=on.
    (optionalAttrs hasConfigTxt {
      hardware.raspberry-pi.config.all = {
        base-dt-params = {

          # SPI0 → /dev/spidev0.0, the JLX12864 LCD bus.
          spi = {
            enable = true;
            value = "on";
          };

          # I2C-1 → /dev/i2c-1, the ICM20948 IMU (read by RTIMULib).
          i2c_arm = {
            enable = true;
            value = "on";
          };

          # If the IMU drops off the bus (bursts of "I2C read error from 104"
          # then a frozen heading on the LCD), the BCM2835 clock-stretch bug is a
          # prime suspect. Halving the bus speed mitigates it; uncomment:
          #
          # i2c_arm_baudrate = { enable = true; value = "50000"; };  # 100k → 50k
        };

        # Free the PL011 (ttyAMA0) for the arduino_servo motor controller at
        # 38400 bd: move Bluetooth off the UART. nixos-raspberrypi keeps the
        # serial console off this UART, so it carries data, not a login.
        dt-overlays.disable-bt = {
          enable = true;
          params = { };
        };
      };
    })
  ]);
}
