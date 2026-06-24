# opencpn — chartplotter initial configuration.
#
# opencpn is a desktop GUI, not a daemon: this module installs it (plus any
# plugin packages) and seeds an initial ~/.opencpn/opencpn.conf wiring the NMEA
# feed from signalk. The conf is copied only if absent, so edits the user later
# makes through the GUI are preserved.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation.opencpn;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    concatStringsSep
    ;

  nav = config.services.navigation;

  # Signal K hub port OpenCPN connects to (declared by the signalk module).
  signalkPort = nav.signalk.port or 3000;

  # Bench-proven 24-field ConnectionParams (OpenCPN 5.12). Seed both links the
  # helm used to wire by hand, gated on the matching service so they vanish when
  # it is off:
  #   - Signal K hub (input): position/AIS/sensors over the Signal K protocol.
  #   - pypilot (in/out): autopilot heading/commands over TCP NMEA0183 (:20220).
  # pypilot -> Signal K stays automatic (signalk.nix adds the :20220 provider).
  signalkConn = "1;3;localhost;${toString signalkPort};0;;4800;1;0;0;;0;;0;0;0;0;1;;1;;0;0;";
  pypilotConn = "1;0;localhost;20220;0;;4800;1;1;0;;0;;0;0;0;0;1;;1;;0;0;";

  defaultConnections =
    lib.optional (nav.signalk.enable or false) signalkConn
    ++ lib.optional (nav.pypilot.enable or false) pypilotConn;

  user = config.users.users.${cfg.user};
  home = user.home or "/home/${cfg.user}";
  group = user.group or "users";

  # Per-plugin enable stanzas. OpenCPN keys plugins by their .so filename and
  # hides ones whose CompatOS differs from the host's; locally-built plugins
  # (e.g. pypilot) report the nixpkgs build target, so the empty value
  # auto-detected on NixOS hides them. Pinning CompatOS + bEnabled=1 makes them
  # load and appear without a manual pass through the GUI.
  pluginEnableSections = concatStringsSep "\n" (
    map (so: ''
      [PlugIns/${so}]
      bEnabled=1'') cfg.enabledPlugins
  );

  # Initial seed: data connections, host plugin-compat and the enabled plugins.
  # opencpn rewrites opencpn.conf on exit, so this only bootstraps the first run;
  # the serialized fields are opencpn-version sensitive (validated on the bench).
  confFile = pkgs.writeText "opencpn.conf" ''
    [Settings]
    CompatOS=${cfg.compatOS}
    CompatOsVersion=${cfg.compatOsVersion}

    [Settings/NMEADataSource]
    DataConnections=${cfg.dataConnection}

    [PlugIns]
    CatalogExpert=1
    LatestCatalogDownloaded=master
    ${pluginEnableSections}
    ${cfg.extraConfig}
  '';

  # OPENCPN_PLUGIN_DIRS *replaces* opencpn's default plugin search path
  # (plugin_paths.cpp), so pointing it at the external plugins alone drops the
  # bundled ones (grib, dashboard…) and the plugin list ends up empty. Fix: merge
  # opencpn AND the plugins into one tree, then point the env at that single
  # `lib/opencpn` (bundled + external together). XDG_DATA_DIRS gets the merged
  # share so each plugin finds its data.
  opencpnPkg =
    if cfg.plugins == [ ] then
      cfg.package
    else
      pkgs.symlinkJoin {
        name = "opencpn-with-plugins";
        paths = [ cfg.package ] ++ cfg.plugins;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/opencpn \
            --set OPENCPN_PLUGIN_DIRS "$out/lib/opencpn" \
            --prefix XDG_DATA_DIRS : "$out/share"
        '';
      };
in
{
  options.services.navigation.opencpn = {
    enable = mkEnableOption "the OpenCPN chartplotter";

    package = mkOption {
      type = types.package;
      default = pkgs.opencpn;
      defaultText = lib.literalExpression "pkgs.opencpn";
      description = "OpenCPN package.";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      default = opencpnPkg;
      defaultText = lib.literalExpression "<package> (cfg.package wrapped with plugins)";

      # The bare cfg.package binary ignores OPENCPN_PLUGIN_DIRS; only this
      # wrapper sets it. Everything that launches OpenCPN (desktop buttons,
      # autostart, keybinds) MUST use finalPackage, else plugins vanish.
      description = "OpenCPN package actually launched: cfg.package, wrapped with the merged plugin search path when plugins are set.";
    };

    user = mkOption {
      type = types.str;
      description = "User whose ~/.opencpn is seeded and who runs OpenCPN.";
    };

    plugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.opencpn-plugin-pypilot ]";
      description = ''
        Plugin packages installed alongside OpenCPN. Each plugin must export
        its shared library under lib/opencpn/ (and data under
        share/opencpn/plugins/<name>/). Setting this wraps the opencpn binary
        with OPENCPN_PLUGIN_DIRS so plugins are discoverable.
      '';
    };

    nmeaPort = mkOption {
      type = types.port;
      default = 10110;
      description = "signalk NMEA0183 TCP port OpenCPN reads from.";
    };

    dataConnection = mkOption {
      type = types.str;

      # 24-field ConnectionParams::Serialize (OpenCPN 5.12): Type;NetProtocol;
      # addr;port;DataProtocol;serialPort;baud;checksum;ioSelect;inListType;
      # inList;outListType;outList;prio;garmin;garminUp;furuno;enabled;comment;
      # autoSKDiscover;socketCAN;noDataReconnect;disableEcho;authToken.
      # Default: the Signal K + pypilot links wired above, joined with `|`. Older
      # 6-field strings are rejected as invalid by OpenCPN.
      default = concatStringsSep "|" defaultConnections;
      defaultText = lib.literalExpression "<Signal K + pypilot connections, gated on each service>";

      description = ''
        Serialized opencpn.conf DataConnections entry (24 fields, OpenCPN 5.12
        ConnectionParams format). Join multiple connections with `|`. The format
        is version-sensitive: if a seeded value is rejected, create the connection
        once in the GUI and copy its `DataConnections=` line here.
      '';
    };

    enabledPlugins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "libpypilot_pi.so" ];
      description = ''
        Plugin shared-object names marked enabled in the seeded opencpn.conf
        (`[PlugIns/<name>] bEnabled=1`). Pair with `plugins`; without this the
        plugin ships but stays absent from OpenCPN's list until enabled by hand.
      '';
    };

    compatOS = mkOption {
      type = types.str;
      default = "debian-arm64";
      description = ''
        Host CompatOS string OpenCPN uses to judge plugin compatibility. The
        bundled plugins report the nixpkgs build target; the empty value
        auto-detected on NixOS hides them, so pin the matching value (verified on
        the Pi bench: debian-arm64).
      '';
    };

    compatOsVersion = mkOption {
      type = types.str;
      default = "12";
      description = "CompatOsVersion paired with compatOS (Debian 12 on the bench).";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Extra lines appended verbatim to the seeded opencpn.conf.";
    };
  };

  config = mkIf cfg.enable {
    # opencpnPkg already merges the plugins (symlinkJoin), so don't add them again.
    environment.systemPackages = [ opencpnPkg ];

    # Create the config dir and copy the conf only when it does not yet exist
    # (tmpfiles `C`), leaving GUI-written settings untouched on later boots.
    systemd.tmpfiles.rules = [
      "d ${home}/.opencpn 0755 ${cfg.user} ${group} -"
      "C ${home}/.opencpn/opencpn.conf 0644 ${cfg.user} ${group} - ${confFile}"
    ];
  };
}
