# SIM7600X 4G/LTE HAT — cellular uplink for the navigation stack.
#
# TODO: not implemented yet. Planned interfaces:
#  - UART0 (ttyAMA0) or USB CDC : AT command / PPP modem channel.
#  - GPIO : power-on key, flight-mode/reset lines.
#  - NetworkManager/ModemManager wiring for the WWAN interface.

{ config, lib, ... }:

let
  cfg = config.services.navigation;
  inherit (lib) mkIf;
in
{
  config = mkIf cfg.hardware.hats.enableSim7600x {

    # UART0 modem channel; conflicts with any HAT also driving the PL011.
    services.navigation.hardware.gpioClaims = [
      {
        owner = "sim7600x-hat";
        pins = [
          14
          15
        ];
      }
    ];

    # TODO: enable the UART/USB modem, ModemManager and the PPP/WWAN link.
  };
}
