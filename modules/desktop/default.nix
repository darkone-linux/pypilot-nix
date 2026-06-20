# desktop/default.nix — on-board graphical session (options + shared base).
#
# A boat chartplotter needs an always-on desktop. Two interchangeable paths,
# selected by `compositor` and implemented in sibling modules:
#
#   labwc   — Minimal Wayland compositor (RPi OS direction), waybar panel.
#             Lighter, runs OpenCPN through Xwayland. Default. See ./labwc.nix.
#   gnome   — Full GNOME desktop (GDM autologin, GNOME Shell). Best app compat,
#             heavier; kept for Pi 5 experiments. See ./gnome.nix.
#
# This file owns the shared options, the compositor-agnostic packages, and the
# `alwaysOn` block that keeps the screen lit forever. Each compositor module
# guards itself on `cfg.compositor`, so exactly one activates.

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
    mkOption
    mkEnableOption
    mkDefault
    types
    ;
in
{
  imports = [
    ./labwc.nix
    ./gnome.nix
  ];

  options.services.navigation.desktop = {
    enable = mkEnableOption "the on-board graphical desktop (labwc or GNOME)";

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

  config = mkIf cfg.enable (
    lib.mkMerge [
      # ---- shared (compositor-agnostic) ----
      {
        # OpenCPN runs as the session user when the desktop drives it.
        services.navigation.opencpn.user = mkIf opencpn.enable (mkDefault cfg.user);

        environment.systemPackages = [
          pkgs.xygrib
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
    ]
  );
}
