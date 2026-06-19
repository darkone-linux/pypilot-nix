# Pypilot HAT — IMU and control head for the pypilot autopilot.
#
# Buses exercised:
#  - I2C-1 : ICM20948 IMU, read from userspace by RTIMULib (raw /dev/i2c-1).
#  - SPI0  : JLX12864 LCD (ST7565) driven by pypilot's hat/ugfx via spidev.
#  - GPIO  : keypad, 433 MHz RF receiver, buzzer.
#
# Overlay node enables and access groups are the declarative baseline; exact
# pinout is validated on the bench (level 3).

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  inherit (lib) mkIf;
in
{
  config = mkIf (cfg.hardware == "pypilot-hat") {

    # ICM20948 sits on I2C-1; RTIMULib reaches it through /dev/i2c-1, so only
    # bus access (i2c-dev + i2c group) is needed, no kernel IMU driver.
    hardware.i2c.enable = true;

    # spidev exposes the LCD bus to pypilot's display code.
    boot.kernelModules = [ "spidev" ];

    hardware.deviceTree = {
      enable = true;

      # Enable the i2c1 and spi0 controllers (shipped disabled in the base DT);
      # equivalent to dtparam=i2c_arm=on,spi=on.
      overlays = [
        {
          name = "pypilot-hat-i2c1";
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
          name = "pypilot-hat-spi0";
          dtsText = ''
            /dts-v1/;
            /plugin/;
            / {
              compatible = "brcm,bcm2835";
              fragment@0 {
                target = <&spi0>;
                __overlay__ { status = "okay"; };
              };
              fragment@1 {
                target = <&spidev0>;
                __overlay__ { status = "okay"; };
              };
            };
          '';
        }
      ];
    };

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
    '';

    # i2c-tools for bench bring-up (i2cdetect on the IMU).
    environment.systemPackages = [ pkgs.i2c-tools ];
  };
}
