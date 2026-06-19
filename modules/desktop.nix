# desktop.nix — on-board graphical session (Wayland / labwc or wayfire).
#
# A boat chartplotter needs a lightweight, always-on desktop. Supports two
# compositors:
#
#   labwc   — the Raspberry Pi OS Wayland direction; uses an XDG autostart
#             shell script.
#   wayfire — wlroots compositor with wf-shell (panel + background).
#
# No matter the compositor, the screen must NEVER blank or sleep, so `alwaysOn`
# masks every suspend path, tells logind to ignore idle/lid, stops console
# blanking and configures no idle/DPMS for the compositor.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation.desktop;
  opencpn = config.services.navigation.opencpn;
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkEnableOption
    mkDefault
    types
    concatStringsSep
    optional
    ;

  compositorCmd =
    if cfg.compositor == "labwc" then "${pkgs.labwc}/bin/labwc" else "${pkgs.wayfire}/bin/wayfire";

  # Shared autostart entries for labwc's XDG shell script.
  labwcAutostartLines = [
    "${pkgs.waybar}/bin/waybar &"
    "${pkgs.pcmanfm}/bin/pcmanfm --desktop &"
  ]
  ++ optional (opencpn.enable && cfg.autostartOpencpn) "${opencpn.package}/bin/opencpn &"
  ++ cfg.autostart;

  # Generate wayfire.ini — the INI config file path is /etc/xdg/wayfire.ini.
  wayfireIni =
    let
      autostartEntries = [
        {
          key = "wf-shell";
          value = "${pkgs.wayfirePlugins.wf-shell}/bin/wf-shell";
        }
        {
          key = "waybar";
          value = "${pkgs.waybar}/bin/waybar";
        }
        {
          key = "pcmanfm";
          value = "${pkgs.pcmanfm}/bin/pcmanfm --desktop";
        }
      ]
      ++ optional (opencpn.enable && cfg.autostartOpencpn) {
        key = "opencpn";
        value = "${opencpn.package}/bin/opencpn";
      }
      ++ lib.imap0 (i: cmd: {
        key = "extra-${toString i}";
        value = cmd;
      }) cfg.autostart;
    in
    ''
      [core]
      xwayland = true

      [autostart]
      ${concatStringsSep "\n" (map (e: "${e.key} = ${e.value}") autostartEntries)}

      [input]
      xkb_layout = ${config.services.xserver.xkb.layout}
    '';
in
{
  options.services.navigation.desktop = {
    enable = mkEnableOption "the on-board graphical desktop (Wayland / labwc or wayfire)";

    user = mkOption {
      type = types.str;
      default = "skipper";
      description = "User auto-logged into the graphical session.";
    };

    compositor = mkOption {
      type = types.enum [
        "labwc"
        "wayfire"
      ];
      default = "labwc";
      description = "Wayland compositor.";
    };

    alwaysOn = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Keep the screen lit forever: no blanking, no DPMS, no system suspend.
        Mandatory aboard — the chartplotter must stay visible at all times.
      '';
    };

    autostartOpencpn = mkOption {
      type = types.bool;
      default = false;
      description = "Launch OpenCPN on session start (off by default — open it manually).";
    };

    autostart = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "chromium --kiosk http://localhost:3000" ];
      description = "Extra shell commands appended to the compositor autostart.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # ---- labwc-specific ----
    (mkIf (cfg.compositor == "labwc") {
      # labwc autostart: panel, file manager, navigation apps.
      environment.etc."xdg/labwc/autostart".text = concatStringsSep "\n" labwcAutostartLines + "\n";

      # Keyboard layout for the Wayland session follows the system setting.
      environment.etc."xdg/labwc/environment".text =
        "XKB_DEFAULT_LAYOUT=${config.services.xserver.xkb.layout}\n";

      environment.systemPackages = [ pkgs.labwc ];
    })

    # ---- wayfire-specific ----
    (mkIf (cfg.compositor == "wayfire") {
      environment.etc."xdg/wayfire.ini".text = wayfireIni;
      environment.systemPackages = [
        pkgs.wayfire
        pkgs.wayfirePlugins.wf-shell
      ];
    })

    # ---- shared ----
    {
      # Autologin into the compositor at boot; agreety covers a manual re-login.
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = compositorCmd;
            user = cfg.user;
          };
          default_session = {
            command = "${pkgs.greetd}/bin/agreety --cmd ${compositorCmd}";
            user = "greeter";
          };
        };
      };

      # Minimal panel config; a broken panel must not take the session down.
      environment.etc."xdg/waybar/config.jsonc".text = builtins.toJSON {
        layer = "top";
        position = "top";
        modules-left = [ "wlr/taskbar" ];
        modules-center = [ "clock" ];
        modules-right = [
          "cpu"
          "memory"
          "tray"
        ];
      };
      environment.etc."xdg/waybar/style.css".text = "";

      # OpenCPN runs as the session user when the desktop drives it.
      services.navigation.opencpn.user = mkIf opencpn.enable (mkDefault cfg.user);

      environment.systemPackages = [
        pkgs.waybar
        pkgs.pcmanfm
        pkgs.foot

        # OpenCPN is a wxWidgets/X11 app; compositors launch it through Xwayland.
        pkgs.xwayland

        # Helm workstation apps: web consoles (SignalK/pypilot), PDFs, media.
        pkgs.chromium
        pkgs.evince
        pkgs.vlc
      ];

      # Wayland graphics stack and a base font for the panel/menus.
      hardware.graphics.enable = mkDefault true;
      fonts.packages = [ pkgs.dejavu_fonts ];
    }

    # ---- always-on (compositor-agnostic) ----
    (mkIf cfg.alwaysOn {
      # 1. Forbid every system sleep/hibernate path.
      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };
      powerManagement.enable = false;

      # 2. logind ignores inactivity and the lid switch.
      services.logind.settings.Login = {
        IdleAction = "ignore";
        HandleLidSwitch = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandleLidSwitchExternalPower = "ignore";
      };

      # 3. No TTY blanking before the compositor takes over.
      boot.kernelParams = [ "consoleblank=0" ];
    })
  ]);
}
