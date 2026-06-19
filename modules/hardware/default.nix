# Hardware HAT selector.
#
# Declares services.navigation.hardware and imports the per-HAT modules. Each
# HAT activates only when selected, so a single enum drives the whole board.

{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  imports = [
    ./pypilot-hat.nix
    ./macarthur-hat.nix
  ];

  options.services.navigation.hardware = mkOption {
    type = types.nullOr (
      types.enum [
        "pypilot-hat"
        "macarthur-hat"
      ]
    );
    default = null;
    example = "macarthur-hat";
    description = ''
      HAT fitted on the Raspberry Pi. Selecting one enables the buses it needs
      (I2C/SPI/UART), loads the matching kernel modules and applies the
      device-tree overlays. `null` configures no HAT.
    '';
  };
}
