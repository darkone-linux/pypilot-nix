# desktop.nix — on-board graphical session (GNOME or labwc Wayland).
#
# A boat chartplotter needs an always-on desktop. Two paths:
#
#   gnome   — Full GNOME desktop (GDM autologin, GNOME Shell, Wayland).
#             Best app compat, built-in panel. App set trimmed and dock pinned
#             to the navigation apps.
#   labwc   — Minimal Wayland stacking compositor (RPi OS direction), waybar
#             panel. Lighter, runs OpenCPN through Xwayland.
#
# Either way the screen must NEVER blank or sleep, so `alwaysOn` masks every
# suspend path, tells logind to ignore idle/lid, stops console blanking, and
# (GNOME) locks the screensaver/idle keys off via dconf.

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

  # Hide an installed app from the GNOME app grid without uninstalling it:
  # a NoDisplay launcher at the same path, higher priority so it wins the
  # profile collision and shadows the real one. Harmless if the app is absent.
  hideApp =
    id:
    lib.hiPrio (
      pkgs.writeTextFile {
        name = "hide-${id}";
        destination = "/share/applications/${id}.desktop";
        text = ''
          [Desktop Entry]
          Type=Application
          Name=${id}
          NoDisplay=true
          Exec=true
        '';
      }
    );
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
        pkgs.pcmanfm
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
      services.displayManager.autoLogin = {
        enable = true;
        user = cfg.user;
      };

      # Trim GNOME's default app set to a chartplotter-relevant minimum.
      environment.gnome.excludePackages = with pkgs; [
        gnome-tour
        gnome-user-docs
        yelp
        epiphany
        geary
        totem
        gnome-music
        gnome-maps
        gnome-weather
        gnome-contacts
        gnome-calendar
        simple-scan
        gnome-software
      ];

      # No NixOS manual / info docs on an appliance.
      documentation.nixos.enable = false;

      # Dock favorites and always-on, via dconf system defaults.
      programs.dconf.profiles.user.databases = [
        # Pinned launchers (default only — the skipper may re-pin).
        {
          lockAll = false;
          settings."org/gnome/shell".favorite-apps = [
            "opencpn.desktop"
            "xygrib.desktop"
            "org.gnome.Nautilus.desktop"
          ];
        }
      ]
      ++ optional cfg.alwaysOn {
        # Screen always lit, enforced (locked) — mandatory aboard.
        lockAll = true;
        settings = {
          "org/gnome/desktop/session"."idle-delay" = lib.gvariant.mkUint32 0;
          "org/gnome/desktop/screensaver".lock-enabled = false;
          "org/gnome/desktop/lockdown".disable-lock-screen = true;
          "org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";
          "org/gnome/settings-daemon/plugins/power".sleep-inactive-battery-type = "nothing";
        };
      };

      # OpenCPN autostart entry (only when requested).
      environment.etc = optionalAttrs (opencpn.enable && cfg.autostartOpencpn) {
        "xdg/autostart/opencpn.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=OpenCPN
          Exec=${opencpn.package}/bin/opencpn
          X-GNOME-Autostart-enabled=true
        '';
      };

      # Hide a few installed-but-noisy launchers from the grid (kept reachable
      # as default handlers, e.g. evince for PDFs).
      environment.systemPackages = map hideApp [
        "vim"
        "gvim"
        "org.gnome.Evince"
        "org.gnome.Extensions"
        "org.gnome.Settings"
      ];
    })

    # ---- shared ----
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
  ]);
}
