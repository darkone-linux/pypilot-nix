# desktop.nix — on-board graphical session (Wayland / labwc).
#
# A boat chartplotter needs a lightweight, always-on desktop: labwc (the
# Raspberry Pi OS Wayland direction) with a panel, a file manager and the
# navigation apps launched on login. The screen must NEVER blank or sleep, so
# `alwaysOn` masks every suspend path, tells logind to ignore idle/lid, stops
# console blanking and configures no idle/DPMS for the compositor.

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

  labwc = "${pkgs.labwc}/bin/labwc";

  # labwc reads autostart/environment from XDG config dirs (/etc/xdg/labwc).
  # Failures here never abort the session, so the desktop comes up regardless.
  autostartLines = [
    "${pkgs.waybar}/bin/waybar &"
    "${pkgs.pcmanfm}/bin/pcmanfm --desktop &"
  ]
  ++ optional opencpn.enable "${opencpn.package}/bin/opencpn &"
  ++ cfg.autostart;
in
{
  options.services.navigation.desktop = {
    enable = mkEnableOption "the on-board graphical desktop (Wayland/labwc)";

    user = mkOption {
      type = types.str;
      default = "skipper";
      description = "User auto-logged into the graphical session.";
    };

    compositor = mkOption {
      type = types.enum [ "labwc" ];
      default = "labwc";
      description = "Wayland compositor (labwc; wayfire planned).";
    };

    alwaysOn = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Keep the screen lit forever: no blanking, no DPMS, no system suspend.
        Mandatory aboard — the chartplotter must stay visible at all times.
      '';
    };

    autostart = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "chromium --kiosk http://localhost:3000 &" ];
      description = "Extra shell commands appended to the labwc autostart.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Autologin straight into labwc at boot; agreety covers a manual re-login.
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = labwc;
            user = cfg.user;
          };
          default_session = {
            command = "${pkgs.greetd}/bin/agreety --cmd ${labwc}";
            user = "greeter";
          };
        };
      };

      # labwc autostart: panel, file manager, navigation apps.
      environment.etc."xdg/labwc/autostart".text = concatStringsSep "\n" autostartLines + "\n";

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
        pkgs.labwc
        pkgs.waybar
        pkgs.pcmanfm
        pkgs.foot

        # OpenCPN is a wxWidgets/X11 app; labwc launches it through Xwayland.
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

      # 4. labwc gets no idle/DPMS rule and no swayidle → the screen stays lit.
    })
  ]);
}
