# navigation.nix — top-level orchestrator for the marine navigation stack.
#
# Single entry point: importing this module and setting
# `services.navigation.enable = true` pulls in the hardware buses, the
# pypilot/signalk/opencpn services and the GPS plumbing (udev symlinks + gpsd),
# and makes the flake's custom packages available through an overlay. The
# individual services are still toggled via their own `enable` options.

{ config, lib, ... }:

let
  cfg = config.services.navigation;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    optional
    types
    ;

  # udev SYMLINK for a USB serial device matched by vendor/product.
  ttySymlink =
    {
      vendorId,
      productId,
      name,
    }:
    ''SUBSYSTEM=="tty", ATTRS{idVendor}=="${vendorId}", ATTRS{idProduct}=="${productId}", SYMLINK+="${name}", TAG+="systemd"'';

  gpsName = lib.removePrefix "/dev/" cfg.gps.device;

  hasGpsIds = cfg.gps.vendorId != null && cfg.gps.productId != null;
  hasMotorIds = cfg.motor.vendorId != null && cfg.motor.productId != null;
in
{
  imports = [
    ./hardware
    ./pypilot.nix
    ./signalk.nix
    ./opencpn.nix
    ./gps-time.nix
  ];

  options.services.navigation = {
    enable = mkEnableOption "the declarative marine navigation stack";

    gps = {
      enable = mkEnableOption "the GPS receiver served by gpsd";

      device = mkOption {
        type = types.str;
        default = "/dev/gps0";
        description = "Device gpsd reads from; matches the udev symlink below when the USB IDs are set.";
      };

      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "1546";
        description = "USB idVendor for the GPS udev symlink. null disables the rule (device wired directly).";
      };

      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "01a7";
        description = "USB idProduct for the GPS udev symlink.";
      };
    };

    motor = {
      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "2341";
        description = "USB idVendor for the autopilot motor-controller symlink. null disables the rule.";
      };

      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "0042";
        description = "USB idProduct for the autopilot motor-controller symlink.";
      };

      symlink = mkOption {
        type = types.str;
        default = "pypilot_motor";
        description = "Name of the /dev symlink pointing at the motor controller.";
      };
    };
  };

  config = mkIf cfg.enable {

    # Expose the flake's custom marine packages so the service modules'
    # `package` defaults (pkgs.pypilot, pkgs.signalk-server, …) resolve.
    nixpkgs.overlays = [ (final: _prev: import ../pkgs final) ];

    # GPS served by gpsd, feeding signalk and the system clock.
    services.gpsd = mkIf cfg.gps.enable {
      enable = true;
      devices = [ cfg.gps.device ];

      # Read immediately; a fix must come up without a client connected.
      nowait = true;
    };

    # Stable /dev names for the USB GPS and motor controller, emitted only when
    # the matching vendor/product IDs are configured.
    services.udev.extraRules = lib.concatStringsSep "\n" (
      optional (cfg.gps.enable && hasGpsIds) (ttySymlink {
        inherit (cfg.gps) vendorId productId;
        name = gpsName;
      })
      ++ optional hasMotorIds (ttySymlink {
        inherit (cfg.motor) vendorId productId;
        name = cfg.motor.symlink;
      })
    );

    assertions = [
      {
        assertion = (cfg.gps.vendorId == null) == (cfg.gps.productId == null);
        message = "services.navigation.gps: set both vendorId and productId, or neither.";
      }
      {
        assertion = (cfg.motor.vendorId == null) == (cfg.motor.productId == null);
        message = "services.navigation.motor: set both vendorId and productId, or neither.";
      }
    ];

    warnings = optional (cfg.pypilot.enable && cfg.hardware == null) (
      "services.navigation: pypilot is enabled without a HAT (hardware = null); "
      + "the IMU and control head will be unavailable."
    );
  };
}
