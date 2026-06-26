# XPT2046 touchscreen HAT — SPI display with resistive touch.
#
# TODO: not implemented yet. Planned interfaces:
#  - SPI0 : framebuffer display (fbtft/DRM) + XPT2046 touch controller.
#  - GPIO : touch IRQ, display backlight.
#  - libinput/udev calibration for the touch panel.

{ config, lib, ... }:

let
  cfg = config.services.navigation;
  inherit (lib) mkIf;
in
{
  config = mkIf cfg.hardware.hats.enableXpt2046 {

    # SPI0 display + touch; conflicts with any HAT also driving SPI0.
    services.navigation.hardware.gpioClaims = [
      {
        owner = "xpt2046-hat";
        pins = [
          7
          8
          9
          10
          11
        ];
      }
    ];

    # TODO: enable the SPI framebuffer, the XPT2046 touch driver and calibration.
  };
}
