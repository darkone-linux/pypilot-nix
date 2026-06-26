# Camera Module 3 Wide — Raspberry Pi CSI camera add-on (IMX708 sensor).
#
# Interfaces:
#  - CSI-2 : IMX708 wide-angle sensor on the camera connector (no 40-pin GPIO).
#  - libcamera/dt-overlay (imx708) feeding the unicam V4L2 capture pipeline.
#
# Sits on the dedicated CSI connector, so it claims no header GPIOs and stays
# compatible with every HAT above (no gpioClaims entry needed).

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
  # (Pi hosts), not on the plain-nixpkgs lab VM. Emit the overlay only where it
  # is declared, so the module stays evaluable everywhere.
  hasConfigTxt = options.hardware ? raspberry-pi;
in
{
  config = mkIf cfg.hardware.modules.enableCamera3Wide (mkMerge [
    {

      # libcamera userspace + the `cam` test tool for bench capture/preview; the
      # sensor is read through the unicam V4L2 nodes (/dev/video*, video group).
      environment.systemPackages = [ pkgs.libcamera ];
    }

    # Pin the IMX708 on the vendor firmware config.txt: turn off the auto-detect
    # guess and load the imx708 overlay explicitly on the CSI port.
    (optionalAttrs hasConfigTxt {
      hardware.raspberry-pi.config.all = {
        options.camera_auto_detect = {
          enable = true;

          # Integer 0, not boolean false: the renderer does `toString value`, and
          # `toString false` is the empty string (→ a blank, ignored directive).
          value = 0;
        };
        dt-overlays.imx708 = {
          enable = true;
          params = { };
        };
      };
    })
  ]);
}
