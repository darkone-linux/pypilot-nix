# gps-time.nix — system clock disciplined from GPS, offline.
#
# A boat has no Internet, so the clock is steered by GPS rather than NTP: gpsd
# (enabled by navigation.nix) exports time over SHM and chrony consumes it as a
# reference clock. SHM gives millisecond accuracy from the NMEA stream; an
# optional PPS pin raises that to microseconds once wired (validated on the
# bench, level 3).
#
# gpsd itself is owned by navigation.nix; this module only adds the chrony side.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  gcfg = cfg.gpsTime;
  inherit (lib)
    mkIf
    mkOption
    optionalString
    types
    ;
in
{
  options.services.navigation.gpsTime = {
    enable = mkOption {
      type = types.bool;
      default = cfg.gps.enable;
      defaultText = lib.literalExpression "config.services.navigation.gps.enable";
      description = "Discipline the system clock from GPS via gpsd + chrony (no NTP needed offline).";
    };

    pps = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use a PPS signal (GPIO) for microsecond accuracy; requires hardware wiring.";
      };

      device = mkOption {
        type = types.str;
        default = "/dev/pps0";
        description = "PPS device chrony locks onto.";
      };
    };
  };

  config = mkIf (cfg.enable && gcfg.enable) {

    services.chrony = {
      enable = true;

      # GPS is the time reference: SHM 0 is the NMEA time gpsd exports. Allow a
      # large initial step (clock may be far off at cold boot) and keep the RTC
      # updated for the next boot without a fix.
      extraConfig = ''
        refclock SHM 0 refid GPS offset 0.5 delay 0.2
        ${optionalString gcfg.pps.enable "refclock PPS ${gcfg.pps.device} lock GPS refid PPS prefer"}
        makestep 1.0 3
        rtcsync
      '';
    };

    # PPS needs the GPIO kernel driver; pps-tools helps diagnose it on the bench.
    boot.kernelModules = mkIf gcfg.pps.enable [ "pps_gpio" ];
    environment.systemPackages = mkIf gcfg.pps.enable [ pkgs.pps-tools ];

    # chrony's SHM segment is populated by gpsd, so start it after gpsd.
    systemd.services.chronyd.after = mkIf cfg.gps.enable [ "gpsd.service" ];
  };
}
