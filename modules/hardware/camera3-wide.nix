# Camera Module 3 Wide — Raspberry Pi CSI camera add-on.
#
# TODO: not implemented yet. Planned interfaces:
#  - CSI-2 : IMX708 sensor via the camera connector (no 40-pin GPIO use).
#  - libcamera/dt-overlay (imx708) and the capture pipeline.
#
# Sits on the dedicated CSI connector, so it claims no header GPIOs and stays
# compatible with every HAT above.

{ config, lib, ... }:

let
  cfg = config.services.navigation;
  inherit (lib) mkIf;
in
{
  config = mkIf cfg.hardware.modules.enableCamera3Wide {

    # TODO: load the imx708 overlay, enable libcamera and the capture stack.
  };
}
