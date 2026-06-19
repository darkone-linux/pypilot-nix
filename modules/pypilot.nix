# pypilot — autopilot daemon service.
#
# Runs the pypilot server (autopilot computation, servo control, NMEA/SignalK
# output) as a dedicated system user. Calibration and configuration live in the
# StateDirectory (/var/lib/pypilot), outside the Nix store, where pypilot writes
# them at runtime.
#
# Requires the flake overlay so `pkgs.pypilot` resolves.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation.pypilot;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    optional
    types
    ;

  stateDir = "/var/lib/pypilot";

  # Shared service skeleton; the daemon and its web UI differ only by binary.
  baseService = exec: {
    serviceConfig = {
      ExecStart = exec;
      User = cfg.user;
      Group = cfg.group;
      StateDirectory = "pypilot";
      WorkingDirectory = stateDir;
      Restart = "on-failure";
      RestartSec = 5;
    };

    environment.HOME = stateDir;
  };
in
{
  options.services.navigation.pypilot = {
    enable = mkEnableOption "the pypilot autopilot daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.pypilot;
      defaultText = lib.literalExpression "pkgs.pypilot";
      description = "pypilot package providing the autopilot daemon.";
    };

    imu = mkOption {
      type = types.enum [
        "icm20948"
        "mpu9250"
        "mpu9255"
      ];
      default = "icm20948";
      description = ''
        IMU model fitted on the HAT. RTIMULib autodetects the sensor on the I2C
        bus, so this is recorded for diagnostics and pinned configuration.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "pypilot";
      description = "User the daemon runs as.";
    };

    group = mkOption {
      type = types.str;
      default = "pypilot";
      description = "Group the daemon runs as.";
    };

    webUi.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Run pypilot_web, the local web configuration interface.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the pypilot NMEA (20220), client (23322) and web (8000) ports.";
    };
  };

  config = mkIf cfg.enable {

    # Auto-provision the default service account only; a custom user is the
    # host's responsibility.
    users.users.${cfg.user} = mkIf (cfg.user == "pypilot") {
      isSystemUser = true;
      group = cfg.group;
      description = "pypilot autopilot daemon";
      home = stateDir;

      # Hardware access (IMU/LCD/keypad/motor); groups exist only when the
      # matching hardware module is active, so add them opportunistically.
      extraGroups = [
        "dialout"
      ]
      ++ optional (config.users.groups ? i2c) "i2c"
      ++ optional (config.users.groups ? spi) "spi"
      ++ optional (config.users.groups ? gpio) "gpio";
    };

    users.groups.${cfg.group} = mkIf (cfg.group == "pypilot") { };

    systemd.services.pypilot = baseService "${cfg.package}/bin/pypilot" // {
      description = "pypilot autopilot daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
    };

    systemd.services.pypilot-web = mkIf cfg.webUi.enable (
      baseService "${cfg.package}/bin/pypilot_web"
      // {
        description = "pypilot web configuration interface";
        wantedBy = [ "multi-user.target" ];
        after = [ "pypilot.service" ];
        wants = [ "pypilot.service" ];
      }
    );

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        20220
        23322
        8000
      ];
    };
  };
}
