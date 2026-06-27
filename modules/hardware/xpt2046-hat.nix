# XPT2046 touchscreen HAT — SPI TFT (ILI9486) + resistive touch.
#
# Covers the ubiquitous Waveshare-style 3.5" 480x320 LCD (and clones): an
# ILI9486 panel and an XPT2046 (ADS7846-compatible) touch controller sharing
# SPI0.
#
# Interfaces brought up here:
#  - SPI0.0 : ILI9486 framebuffer via fbtft (fb_ili9486) -> /dev/fb1.
#  - SPI0.1 : XPT2046/ADS7846 touch via the ads7846 input driver -> /dev/input.
#  - GPIO   : DC (24), RESET (25), touch PENIRQ (17).
#
# A self-contained device-tree overlay wires both chips (no vendor .dtbo needed);
# pins/params follow the waveshare35a overlay. Panels vary a lot (controller,
# resolution, IRQ pin), so this targets the common 3.5" board; other panels need
# the matching compatible/pins (see doc/xpt2046.fr.md).
#
# TODO (see doc/xpt2046.fr.md):
#  - validate on the bench (level 3): controller bind, rotation, touch axes.
#  - variant options for the 2.x/3.2" boards (fb_ili9341, different PENIRQ).
#  - persist a libinput/tslib calibration matrix once measured.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  hat = cfg.xpt2046Hat;
  inherit (lib)
    mkIf
    mkOption
    types
    ;
in
{
  options.services.navigation.xpt2046Hat = {
    rotate = mkOption {
      type = types.enum [
        0
        90
        180
        270
      ];
      default = 0;
      description = "Display rotation in degrees (fbtft `rotate`).";
    };

    spiFrequency = mkOption {
      type = types.ints.positive;
      default = 16000000;
      description = "ILI9486 SPI clock in Hz; lower it if the panel shows noise.";
    };
  };

  config = mkIf cfg.hardware.hats.enableXpt2046 {

    # Pins driven by the HAT: SPI0 (7-11), display DC (24) + RESET (25) and the
    # touch PENIRQ (17). Shares SPI0 with the Pypilot/MacArthur HATs by design,
    # so the conflict assertion refuses those combinations.
    services.navigation.hardware.gpioClaims = [
      {
        owner = "xpt2046-hat";
        pins = [
          7
          8
          9
          10
          11
          17
          24
          25
        ];
      }
    ];

    # fbtft drives the panel, ads7846 the touch; both bind off the overlay's
    # compatible strings once SPI is up.
    boot.kernelModules = [
      "spi-bcm2835"
      "fbtft"
      "fb_ili9486"
      "ads7846"
    ];

    hardware.deviceTree = {
      enable = true;

      # Enable SPI0, disable the default spidev nodes and attach the ILI9486
      # display (CS0) and the ADS7846 touch (CS1). Mirrors waveshare35a.
      overlays = [
        {
          name = "xpt2046-hat";
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
                __overlay__ { status = "disabled"; };
              };

              fragment@2 {
                target = <&spidev1>;
                __overlay__ { status = "disabled"; };
              };

              fragment@3 {
                target = <&gpio>;
                __overlay__ {
                  xpt2046_pins: xpt2046_pins {
                    brcm,pins = <17 24 25>;
                    brcm,function = <0 1 1>;
                  };
                };
              };

              fragment@4 {
                target = <&spi0>;
                __overlay__ {
                  #address-cells = <1>;
                  #size-cells = <0>;

                  ili9486: ili9486@0 {
                    compatible = "ilitek,ili9486";
                    reg = <0>;
                    pinctrl-names = "default";
                    pinctrl-0 = <&xpt2046_pins>;
                    spi-max-frequency = <${toString hat.spiFrequency}>;
                    rotate = <${toString hat.rotate}>;
                    fps = <30>;
                    buswidth = <8>;
                    regwidth = <16>;
                    dc-gpios = <&gpio 24 0>;
                    reset-gpios = <&gpio 25 1>;
                    debug = <0>;
                  };

                  ads7846: ads7846@1 {
                    compatible = "ti,ads7846";
                    reg = <1>;
                    spi-max-frequency = <2000000>;
                    interrupt-parent = <&gpio>;
                    interrupts = <17 2>;
                    pendown-gpio = <&gpio 17 1>;
                    ti,x-plate-ohms = /bits/ 16 <60>;
                    ti,pressure-max = /bits/ 16 <255>;
                    ti,swap-xy;
                  };
                };
              };
            };
          '';
        }
      ];
    };

    # Console + calibration tooling: tslib (ts_calibrate, framebuffer), evtest
    # (raw events), xinput_calibrator + xinput (X11 calibration matrix).
    environment.systemPackages = [
      pkgs.tslib
      pkgs.evtest
      pkgs.xinput_calibrator
      pkgs.xinput
    ];
  };
}
