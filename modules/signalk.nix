# signalk-server — marine data hub service.
#
# Runs signalk-server as a system user with a persistent StateDirectory
# (/var/lib/signalk) holding settings.json, security config and any plugins
# installed at runtime through the web UI. settings.json is seeded from Nix on
# first start only, so later web-UI edits persist.
#
# Requires the flake overlay so `pkgs.signalk-server` resolves.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation.signalk;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    optional
    optionals
    types
    ;

  stateDir = "/var/lib/signalk";

  settingsFormat = pkgs.formats.json { };

  # AIS lives on the navigation module; read it defensively so signalk stays
  # usable when imported without the navigation orchestrator.
  navAis = config.services.navigation.ais or null;
  aisSerial = navAis != null && navAis.enable;
  aisSdr = navAis != null && navAis.sdr.enable;

  # One NMEA0183 input provider (serial or udp), mirroring OpenPlotter's layout.
  nmea0183Provider = id: subOptions: {
    inherit id;
    enabled = true;
    pipeElements = [
      {
        type = "providers/simple";
        options = {
          logging = false;
          type = "NMEA0183";
          inherit subOptions;
        };
      }
    ];
  };

  # pypilot autopilot as a TCP NMEA0183 source (port 20220).
  pypilotProviders = optionals cfg.pypilotIntegration [
    {
      id = "pypilot";
      enabled = true;
      pipeElements = [
        {
          type = "providers/tcp";
          options = {
            host = "localhost";
            port = 20220;
          };
        }
      ];
    }
  ];

  # AIS from a serial receiver and/or SDR (ais-catcher) over UDP.
  aisProviders =
    optional aisSerial (
      nmea0183Provider "ais" {
        type = "serial";
        device = navAis.device;
        baudrate = navAis.baudrate;
        validateChecksum = true;
      }
    )
    ++ optional aisSdr (
      nmea0183Provider "ais-sdr" {
        type = "udp";
        port = toString navAis.sdr.udpPort;
        validateChecksum = true;
      }
    );

  defaultSettings = {
    interfaces = { };
    ssl = false;
    mdns = true;
    port = cfg.port;
    pipedProviders = pypilotProviders ++ aisProviders;
  };

  settingsFile = settingsFormat.generate "signalk-settings.json" (
    lib.recursiveUpdate defaultSettings cfg.settings
  );
in
{
  options.services.navigation.signalk = {
    enable = mkEnableOption "the Signal K marine data server";

    package = mkOption {
      type = types.package;
      default = pkgs.signalk-server;
      defaultText = lib.literalExpression "pkgs.signalk-server";
      description = "signalk-server package.";
    };

    user = mkOption {
      type = types.str;
      default = "signalk";
      description = "User the server runs as.";
    };

    group = mkOption {
      type = types.str;
      default = "signalk";
      description = "Group the server runs as.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "HTTP/WebSocket API port.";
    };

    pypilotIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Add the pypilot TCP NMEA0183 source (localhost:20220) to the default providers.";
    };

    settings = mkOption {
      type = settingsFormat.type;
      default = { };
      description = ''
        Overrides merged (recursively) over the generated settings.json. Seeded
        into StateDirectory on first start only; delete the file there to
        re-seed from this option.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the API port and the NMEA0183 TCP output (10110, when a connection enables it).";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = mkIf (cfg.user == "signalk") {
      isSystemUser = true;
      group = cfg.group;
      description = "Signal K server";
      home = stateDir;

      # Serial AIS/NMEA devices are group dialout.
      extraGroups = optional aisSerial "dialout";
    };

    users.groups.${cfg.group} = mkIf (cfg.group == "signalk") { };

    systemd.services.signalk = {
      description = "Signal K marine data server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # signalk reads its config dir from this env var; settings persist there.
      environment = {
        HOME = stateDir;
        SIGNALK_NODE_CONFIG_DIR = stateDir;
      };

      # Seed settings.json once; afterwards the running server owns it.
      preStart = ''
        if [ ! -e ${stateDir}/settings.json ]; then
          ${pkgs.coreutils}/bin/cp ${settingsFile} ${stateDir}/settings.json
          ${pkgs.coreutils}/bin/chmod 0644 ${stateDir}/settings.json
        fi
      '';

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/signalk-server";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "signalk";
        WorkingDirectory = stateDir;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.port
        10110
      ];
    };
  };
}
