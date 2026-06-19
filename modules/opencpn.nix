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
    ;

  user = config.users.users.${cfg.user};
  home = user.home or "/home/${cfg.user}";
  group = user.group or "users";

  # Initial NMEA connection to signalk. opencpn rewrites opencpn.conf on exit,
  # so this only bootstraps the first run; the serialized DataConnections field
  # is opencpn-version sensitive and validated on the bench (level 3).
  confFile = pkgs.writeText "opencpn.conf" ''
    [Settings/NMEADataSource]
    DataConnections=${cfg.dataConnection}
    ${cfg.extraConfig}
  '';
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

    user = mkOption {
      type = types.str;
      description = "User whose ~/.opencpn is seeded and who runs OpenCPN.";
    };

    plugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.opencpn-plugin-pypilot ]";
      description = ''
        Plugin packages installed alongside OpenCPN. The pypilot plugin
        (pypilot_pi) is not yet packaged in this flake; add it here once it is.
      '';
    };

    nmeaPort = mkOption {
      type = types.port;
      default = 10110;
      description = "signalk NMEA0183 TCP port OpenCPN reads from.";
    };

    dataConnection = mkOption {
      type = types.str;
      default = "0;2;localhost;${toString cfg.nmeaPort};0;0";
      description = ''
        Serialized opencpn.conf DataConnections entry (type;protocol;host;port;…).
        Default follows the spec; complete/adjust on the bench for the installed
        OpenCPN version.
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Extra lines appended verbatim to the seeded opencpn.conf.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ cfg.plugins;

    # Create the config dir and copy the conf only when it does not yet exist
    # (tmpfiles `C`), leaving GUI-written settings untouched on later boots.
    systemd.tmpfiles.rules = [
      "d ${home}/.opencpn 0755 ${cfg.user} ${group} -"
      "C ${home}/.opencpn/opencpn.conf 0644 ${cfg.user} ${group} - ${confFile}"
    ];
  };
}
