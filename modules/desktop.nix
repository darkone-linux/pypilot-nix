# desktop.nix — on-board graphical session (GNOME or labwc Wayland).
#
# A boat chartplotter needs a lightweight, always-on desktop.
# Supports two paths:
#
#   gnome   — Full GNOME desktop (GDM autologin, GNOME Shell, Wayland).
#             Best app compat, built-in panel, heavier on RAM.
#   labwc   — Wayland stacking compositor (RPi OS direction), waybar panel.
#             Lightweight, runs OpenCPN through Xwayland.
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
    optionalAttrs
    types
    concatStringsSep
    optional
    ;
in
{
  options.services.navigation.desktop = {
    enable = mkEnableOption "the on-board graphical desktop (GNOME or labwc Wayland)";

    user = mkOption {
      type = types.str;
      default = "skipper";
      description = "User auto-logged into the graphical session.";
    };

    compositor = mkOption {
      type = types.enum [
        "labwc"
        "gnome"
      ];
      default = "labwc";
      description = "Desktop environment (labwc Wayland or GNOME).";
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

    # ---- GNOME-specific ----
    (mkIf (cfg.compositor == "gnome") {
      services.desktopManager.gnome.enable = true;
      services.displayManager.gdm.enable = true;
      services.displayManager.autoLogin.enable = true;
      services.displayManager.autoLogin.user = cfg.user;

      # Always-on GNOME settings via dconf (no screen blanking, no lock).
      programs.dconf.enable = true;
      environment.etc = {
        "dconf/db/local".text = ''
          [org/gnome/desktop/session]
          idle-delay=uint32 0

          [org/gnome/desktop/screensaver]
          lock-enabled=false

          [org/gnome/desktop/lockdown]
          disable-lock-screen=true

          [org/gnome/settings-daemon/plugins/power]
          sleep-inactive-ac-type='nothing'
          sleep-inactive-battery-type='nothing'
        '';
        "dconf/db/local.d/locks/always-on".text = ''
          /org/gnome/desktop/session/idle-delay
          /org/gnome/desktop/screensaver/lock-enabled
          /org/gnome/desktop/lockdown/disable-lock-screen
          /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
          /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type
        '';
      }
      # GNOME autostart for OpenCPN.
      // optionalAttrs (opencpn.enable && cfg.autostartOpencpn) {
        "xdg/autostart/opencpn.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=OpenCPN
          Exec=${opencpn.package}/bin/opencpn
          X-GNOME-Autostart-enabled=true
        '';
      };

      environment.systemPackages = with pkgs; [
        gnome-terminal
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
