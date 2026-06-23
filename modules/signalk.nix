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

  # Device wiring lives on the navigation module; read it defensively so signalk
  # stays usable when imported without the navigation orchestrator.
  nav = config.services.navigation or null;
  resolved = if nav != null then nav._resolved or [ ] else [ ];
  navAis = if nav != null then nav.ais else null;
  aisSdr = navAis != null && navAis.sdr.enable;

  # Serial NMEA0183 sources (ais/nmea0183 roles) from the unified registry.
  serialDevices = lib.filter (e: e.role == "ais" || e.role == "nmea0183") resolved;
  hasSerial = serialDevices != [ ];

  # One provider per /dev name: the registry may list several udev matches for
  # the same symlink (e.g. a multi-id AIS autodetect) — keep the first.
  uniqueSerial =
    (lib.foldl'
      (
        acc: e:
        if lib.elem e.name acc.seen then
          acc
        else
          {
            seen = acc.seen ++ [ e.name ];
            out = acc.out ++ [ e ];
          }
      )
      {
        seen = [ ];
        out = [ ];
      }
      serialDevices
    ).out;

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

  # gpsd as the GPS source: gpsd owns the serial port (and feeds the clock);
  # signalk reads position/time over the gpsd protocol, no manual connection.
  gpsdProviders = optional cfg.gpsdSource {
    id = "gpsd";
    enabled = true;
    pipeElements = [
      {
        type = "providers/gpsd";
        options = {
          host = "localhost";
          port = "2947";
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

  # Serial NMEA0183 inputs (AIS + sensors) from the registry, and AIS over SDR
  # (ais-catcher) via UDP.
  aisProviders =
    map (
      e:
      nmea0183Provider e.signalkId {
        type = "serial";
        device = "/dev/${e.name}";
        baudrate = e.baudrate;
        validateChecksum = true;
      }
    ) uniqueSerial
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
    pipedProviders = gpsdProviders ++ pypilotProviders ++ aisProviders;
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

    gpsdSource = mkOption {
      type = types.bool;
      default = config.services.navigation.gps.enable or false;
      defaultText = lib.literalExpression "config.services.navigation.gps.enable";
      description = "Add a gpsd source (localhost:2947) so the GPS adopted by gpsd reaches Signal K without a manual connection.";
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
      extraGroups = optional hasSerial "dialout";
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
