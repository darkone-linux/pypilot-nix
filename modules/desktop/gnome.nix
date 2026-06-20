# desktop/gnome.nix — full GNOME session (GDM autologin, GNOME Shell).
#
# Active only when `compositor == "gnome"`. Best app compatibility and a
# built-in panel, at a higher resource cost than labwc — kept mainly for Pi 5
# experiments. Trims the default app set, pins the navigation apps to the dock,
# and (via the shared `alwaysOn`) locks the screensaver/idle keys off.

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
    optional
    optionalAttrs
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
mkIf (cfg.enable && cfg.compositor == "gnome") {
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
}
