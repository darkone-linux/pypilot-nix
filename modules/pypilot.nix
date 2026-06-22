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

    # pypilot's hat process shells out to `renice` to lower its own priority.
    path = [ pkgs.util-linux ];
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

    controlHead.enable = mkOption {
      type = types.bool;
      default = config.services.navigation.hardware == "pypilot-hat";
      defaultText = lib.literalExpression ''config.services.navigation.hardware == "pypilot-hat"'';
      description = ''
        Run pypilot_hat, the control-head process driving the Pypilot HAT's LCD,
        keypad, IR and 433 MHz RF receiver (software-decoded over GPIO). Required
        to pair the RF remote. Defaults on when the Pypilot HAT is fitted.
      '';
    };

    controlHead.lcd = mkOption {
      type = types.enum [
        "none"
        "nokia5110"
        "jlx12864"
        "ssd1309"
        "dg240160"
      ];
      default = "jlx12864";
      description = ''
        LCD driver passed to pypilot_hat. The Pypilot HAT fits a JLX12864
        (ST7565) on SPI0; the vendor firmware enables SPI (see pypilot-hat.nix)
        and pypilot's ugfx ships the spiscreen driver, so the screen works.
        Set to "none" for a headless control head (keypad/IR/RF only) if no LCD
        is fitted.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the pypilot NMEA (20220), client (23322) and web (8000) ports.";
    };
  };

  config = mkIf cfg.enable {

    # Expose pypilot_* (client, scope, calibration…) on the CLI; the daemon runs
    # from its store path, so without this nothing pypilot is on PATH.
    environment.systemPackages = [ cfg.package ];

    # pypilot_pi (OpenCPN plugin) connects to the bare hostname "pypilot" when
    # no host is configured (pypilot_client.cpp: host.empty() -> "pypilot").
    # Co-located here, so resolve it to loopback; else the plugin stays
    # "Disconnected" despite the server listening on 23322.
    networking.hosts."127.0.0.1" = [ "pypilot" ];

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

    # Control head: drives the HAT's LCD and keypad, and listens to the IR and
    # 433 MHz RF receivers; this is what records the remote's codes when pairing.
    # The LCD driver argument selects the panel (jlx12864) or "none" (headless).
    systemd.services.pypilot-hat = mkIf cfg.controlHead.enable (
      lib.recursiveUpdate (baseService "${cfg.package}/bin/pypilot_hat ${cfg.controlHead.lcd}") {
        description = "pypilot HAT control head (LCD, keypad, IR, 433 MHz RF)";
        wantedBy = [ "multi-user.target" ];
        after = [ "pypilot.service" ];
        wants = [ "pypilot.service" ];

        # pypilot_hat exits 0 when it rewrites its pilot list (first run, or any
        # config change via the web UI); "on-failure" leaves the LCD frozen, so
        # restart unconditionally to keep the control head live.
        serviceConfig.Restart = "always";
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
