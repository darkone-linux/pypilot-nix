# Pypilot HAT — IMU and control head for the pypilot autopilot.
#
# Buses exercised:
#  - I2C-1 : ICM20948 IMU, read from userspace by RTIMULib (raw /dev/i2c-1).
#  - SPI0  : JLX12864 LCD (ST7565) driven by pypilot's hat/ugfx via spidev.
#  - UART0 : PL011 (ttyAMA0) → arduino_servo motor controller at 38400 bd.
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

    # The motor controller (arduino_servo) talks on the PL011 (ttyAMA0) at
    # 38400 bd; it must carry data, not a login console. Freeing it from
    # Bluetooth needs `dtoverlay=disable-bt` plus dropping `console=serial0`
    # from the firmware cmdline (host config) — validated on the bench (level 3).
    systemd.services."serial-getty@ttyAMA0".enable = false;

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

          # The mainline bcm2711 DTB exports SPI0 as symbol `spi` (not `spi0`)
          # and has no `spidev0` symbol, so enable `&spi` and declare the spidev
          # child inline. `rohm,dh2228fv` is the spidev driver's generic match
          # (a bare `spidev` compatible is refused by recent kernels).
          dtsText = ''
            /dts-v1/;
            /plugin/;
            / {
              compatible = "brcm,bcm2835";
              fragment@0 {
                target = <&spi>;
                __overlay__ {
                  status = "okay";
                  #address-cells = <1>;
                  #size-cells = <0>;

                  spidev@0 {
                    compatible = "rohm,dh2228fv";
                    reg = <0>;
                    spi-max-frequency = <2000000>;
                    status = "okay";
                  };
                };
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

      # Stable name for the motor controller, matching OpenPlotter's convention;
      # fe201000.serial is the BCM2711 (Pi 4) PL011 instance (Pi 5 differs).
      KERNEL=="ttyAMA[0-9]*", KERNELS=="fe201000.serial:0.0", SYMLINK+="ttyOP_pilot", GROUP="dialout", MODE="0660"
    '';

    # i2c-tools for bench bring-up (i2cdetect on the IMU).
    environment.systemPackages = [ pkgs.i2c-tools ];
  };
}
