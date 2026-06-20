# desktop.nix — on-board graphical session (Openbox X11 or labwc Wayland).
#
# A boat chartplotter needs a lightweight, always-on desktop.
# Supports two paths:
#
#   openbox — X11 stacking WM, native OpenCPN, polybar panel.
#   labwc   — Wayland stacking compositor (RPi OS direction), waybar panel,
#             runs OpenCPN through Xwayland.
#
# No matter the path, the screen must NEVER blank or sleep, so `alwaysOn`
# masks every suspend path, tells logind to ignore idle/lid, stops console
# blanking and (on X11) runs xset -dpms.

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
    optionalString
    ;
in
{
  options.services.navigation.desktop = {
    enable = mkEnableOption "the on-board graphical desktop (Openbox X11 or labwc Wayland)";

    user = mkOption {
      type = types.str;
      default = "skipper";
      description = "User auto-logged into the graphical session.";
    };

    compositor = mkOption {
      type = types.enum [
        "labwc"
        "openbox"
      ];
      default = "labwc";
      description = "Display server and WM (labwc Wayland or Openbox X11).";
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
      description = "Extra shell commands appended to the session autostart.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # ---- labwc-specific (Wayland) ----
    (mkIf (cfg.compositor == "labwc") {
      # labwc autostart: panel, file manager, navigation apps.
      environment.etc."xdg/labwc/autostart".text =
        concatStringsSep "\n" (
          [
            "${pkgs.waybar}/bin/waybar &"
            "${pkgs.pcmanfm}/bin/pcmanfm --desktop &"
          ]
          ++ optional (opencpn.enable && cfg.autostartOpencpn) "${opencpn.package}/bin/opencpn &"
          ++ cfg.autostart
        )
        + "\n";

      # Keyboard layout for the Wayland session follows the system setting.
      environment.etc."xdg/labwc/environment".text =
        "XKB_DEFAULT_LAYOUT=${config.services.xserver.xkb.layout}\n";

      environment.systemPackages = [
        pkgs.labwc
        pkgs.waybar
        pkgs.foot
        pkgs.xwayland
      ];

      # Autologin into the compositor at boot; agreety covers a manual re-login.
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${pkgs.labwc}/bin/labwc";
            user = cfg.user;
          };
          default_session = {
            command = "${pkgs.greetd}/bin/agreety --cmd ${pkgs.labwc}/bin/labwc";
            user = "greeter";
          };
        };
      };
    })

    # ---- openbox-specific (X11) ----
    (mkIf (cfg.compositor == "openbox") {
      services.xserver.enable = true;
      services.xserver.displayManager.autoLogin.enable = true;
      services.xserver.displayManager.autoLogin.user = cfg.user;
      services.xserver.windowManager.openbox.enable = true;

      # Openbox autostart: panel, desktop, navigation apps.
      environment.etc."xdg/openbox/autostart".text = ''
        # X11 screen blanking and DPMS off (always-on display).
        ${pkgs.xorg.xset}/bin/xset -dpms s off s noblank &

        ${pkgs.polybar}/bin/polybar main &
        ${pkgs.pcmanfm}/bin/pcmanfm --desktop &
      ''
      + optionalString (opencpn.enable && cfg.autostartOpencpn) ''
        ${opencpn.package}/bin/opencpn &
      ''
      + concatStringsSep "\n" (map (cmd: "${cmd} &") cfg.autostart)
      + "\n";

      # Minimal polybar panel: clock, CPU, memory, system tray.
      environment.etc."xdg/polybar/config.ini".text = ''
        [bar/main]
        width = 100%
        height = 24
        background = #222222
        foreground = #efefef
        font-0 = DejaVu Sans Mono:size=10

        modules-left =
        modules-center = clock
        modules-right = cpu memory tray

        [module/clock]
        type = internal/date
        interval = 1
        date = %H:%M
        date-alt = %Y-%m-%d %H:%M:%S
        label = %date%

        [module/cpu]
        type = internal/cpu
        interval = 2
        format = CPU: <label> <bar-load>
        label = %percentage:2%%

        [module/memory]
        type = internal/memory
        interval = 2
        format = MEM: <label> <bar-used>
        label = %percentage_used:2%%

        [module/tray]
        type = internal/tray
      '';

      environment.systemPackages = [
        pkgs.openbox
        pkgs.polybar
        pkgs.xterm
      ];
    })

    # ---- shared ----
    {
      # OpenCPN runs as the session user when the desktop drives it.
      services.navigation.opencpn.user = mkIf opencpn.enable (mkDefault cfg.user);

      environment.systemPackages = [
        pkgs.pcmanfm
        pkgs.chromium
        pkgs.evince
        pkgs.vlc
      ];

      # Wayland/Wayfire/X11/XWayland graphics stack.
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
