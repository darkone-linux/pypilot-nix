# desktop/labwc.nix — minimal Wayland session, themed for the helm.
#
# Active only when `compositor == "labwc"`. Builds a polished single-screen
# appliance: solid blue background (swaybg), dark labwc window theme (NavBlue),
# Arc-Dark/Papirus for GTK apps, and a waybar top panel whose left side is a row
# of launcher buttons (OpenCPN, GRIB, terminal, notes, browser, SignalK). A
# right-click root menu lists every app by category. Slow apps (OpenCPN, browser)
# pop a "starting…" notification (mako) so the helmsman doesn't click twice.

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
    concatStringsSep
    optional
    ;

  # Wallpaper blue; `accent` is a touch darker so the focused title bar and the
  # active menu item stand out against the background instead of blending in.
  blue = "#3C4FA2";
  accent = "#2C397A";

  # Raw binaries, full store paths (waybar/labwc inherit no PATH).
  bin = {
    opencpn = "${opencpn.package}/bin/opencpn";
    xygrib = "${pkgs.xygrib}/bin/xygrib";
    terminal = "${pkgs.foot}/bin/foot";
    notes = "${pkgs.xfce.mousepad}/bin/mousepad";
    browser = "${pkgs.chromium}/bin/chromium";
    signalk = "${pkgs.chromium}/bin/chromium --app=http://localhost:3000/";
    files = "${pkgs.pcmanfm}/bin/pcmanfm";
    pdf = "${pkgs.evince}/bin/evince";
    vlc = "${pkgs.vlc}/bin/vlc";
  };

  # Wrap a slow launcher so it flashes a notification before exec'ing — instant
  # feedback that the click registered while the app loads.
  notify =
    name: title: command:
    "${pkgs.writeShellScript "launch-${name}" ''
      ${pkgs.libnotify}/bin/notify-send -t 5000 "${title}" "Démarrage en cours…" || true
      exec ${command}
    ''}";

  # Final launch commands: heavy apps get the notification wrapper, snappy ones
  # run directly.
  launch = {
    opencpn = notify "opencpn" "OpenCPN" bin.opencpn;
    xygrib = notify "xygrib" "XyGrib" bin.xygrib;
    signalk = notify "signalk" "SignalK" bin.signalk;
    browser = notify "browser" "Navigateur" bin.browser;
    terminal = bin.terminal;
    notes = bin.notes;
    files = bin.files;
    pdf = bin.pdf;
    vlc = bin.vlc;
  };

  # labwc window decorations: dark, with the darker blue accent on focus.
  navBlueTheme = pkgs.writeTextDir "share/themes/NavBlue/labwc/themerc" ''
    border.width: 2
    padding.height: 4
    window.active.border.color: ${accent}
    window.inactive.border.color: #2a2e3a
    window.active.title.bg.color: ${accent}
    window.inactive.title.bg.color: #2a2e3a
    window.active.label.text.color: #ffffff
    window.inactive.label.text.color: #b0b4c0
    window.active.button.unpressed.image.color: #ffffff
    window.inactive.button.unpressed.image.color: #b0b4c0
    menu.items.bg.color: #1f2330
    menu.items.text.color: #e6e8ee
    menu.items.active.bg.color: ${accent}
    menu.items.active.text.color: #ffffff
    osd.bg.color: #1f2330
    osd.border.color: ${accent}
    osd.label.text.color: #e6e8ee
  '';
in
mkIf (cfg.enable && cfg.compositor == "labwc") {
  # Background + notification daemon + panel; OpenCPN only when requested.
  environment.etc."xdg/labwc/autostart".text =
    concatStringsSep "\n" (
      [
        "${pkgs.swaybg}/bin/swaybg -c '${blue}' >/dev/null 2>&1 &"
        "${pkgs.mako}/bin/mako >/dev/null 2>&1 &"
        "${pkgs.waybar}/bin/waybar >/dev/null 2>&1 &"
      ]
      ++ optional (opencpn.enable && cfg.autostartOpencpn) "${bin.opencpn} &"
      ++ cfg.autostart
    )
    + "\n";

  # Session env: keyboard follows the system, plus cursor + GTK theme hints.
  environment.etc."xdg/labwc/environment".text = ''
    XKB_DEFAULT_LAYOUT=${config.services.xserver.xkb.layout}
    XCURSOR_THEME=Adwaita
    XCURSOR_SIZE=24
    GTK_THEME=Arc-Dark
  '';

  # labwc core config: NavBlue theme, Super+Return = terminal, right-click root
  # opens the categorized application menu.
  environment.etc."xdg/labwc/rc.xml".text = ''
    <?xml version="1.0"?>
    <labwc_config>
      <theme>
        <name>NavBlue</name>
        <cornerRadius>6</cornerRadius>
        <font name="sans" size="11" />
      </theme>
      <keyboard>
        <keybind key="W-Return">
          <action name="Execute" command="${bin.terminal}" />
        </keybind>
      </keyboard>
      <mouse>
        <context name="Root">
          <mousebind button="Right" action="Press">
            <action name="ShowMenu" menu="root-menu" />
          </mousebind>
        </context>
      </mouse>
    </labwc_config>
  '';

  # Right-click application menu, grouped by category (every installed app).
  environment.etc."xdg/labwc/menu.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <openbox_menu>
      <menu id="root-menu" label="Applications">
        <menu id="menu-nav" label="Navigation">
          <item label="OpenCPN"><action name="Execute"><command>${launch.opencpn}</command></action></item>
          <item label="GRIB (XyGrib)"><action name="Execute"><command>${launch.xygrib}</command></action></item>
          <item label="SignalK"><action name="Execute"><command>${launch.signalk}</command></action></item>
        </menu>
        <menu id="menu-net" label="Internet">
          <item label="Navigateur web"><action name="Execute"><command>${launch.browser}</command></action></item>
        </menu>
        <menu id="menu-media" label="Multimédia">
          <item label="Lecteur VLC"><action name="Execute"><command>${launch.vlc}</command></action></item>
          <item label="Visionneuse PDF"><action name="Execute"><command>${launch.pdf}</command></action></item>
        </menu>
        <menu id="menu-tools" label="Outils">
          <item label="Terminal"><action name="Execute"><command>${launch.terminal}</command></action></item>
          <item label="Notes"><action name="Execute"><command>${launch.notes}</command></action></item>
          <item label="Fichiers"><action name="Execute"><command>${launch.files}</command></action></item>
        </menu>
        <separator />
        <item label="Recharger labwc"><action name="Reconfigure" /></item>
        <item label="Quitter la session"><action name="Exit" /></item>
      </menu>
    </openbox_menu>
  '';

  # GTK apps (pcmanfm, mousepad, xygrib) follow the same dark look.
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Arc-Dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-font-name=Sans 11
    gtk-cursor-theme-name=Adwaita
    gtk-cursor-theme-size=24
  '';

  # Large, readable terminal font — the default was unusably small on the helm.
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=DejaVu Sans Mono:size=18
    pad=8x8

    [colors]
    background=1f2330
    foreground=e6e8ee
  '';

  # Top panel: launcher buttons (left), clock (center), system (right).
  environment.etc."xdg/waybar/config".text = ''
    {
      "layer": "top",
      "position": "top",
      "height": 38,
      "spacing": 6,
      "modules-left": [
        "custom/opencpn", "custom/xygrib", "custom/terminal",
        "custom/notes", "custom/browser", "custom/signalk"
      ],
      "modules-center": [ "clock" ],
      "modules-right": [ "cpu", "memory", "network", "tray" ],
      "custom/opencpn":  { "format": "OpenCPN",  "on-click": "${launch.opencpn}",  "tooltip": false },
      "custom/xygrib":   { "format": "GRIB",     "on-click": "${launch.xygrib}",   "tooltip": false },
      "custom/terminal": { "format": "Terminal", "on-click": "${launch.terminal}", "tooltip": false },
      "custom/notes":    { "format": "Notes",    "on-click": "${launch.notes}",    "tooltip": false },
      "custom/browser":  { "format": "Web",      "on-click": "${launch.browser}",  "tooltip": false },
      "custom/signalk":  { "format": "SignalK",  "on-click": "${launch.signalk}",  "tooltip": false },
      "clock":   { "format": "{:%a %d %b  %H:%M}" },
      "cpu":     { "format": "CPU {usage}%", "interval": 5 },
      "memory":  { "format": "RAM {percentage}%", "interval": 5 },
      "network": {
        "format-wifi": "{essid}",
        "format-ethernet": "{ifname}",
        "format-disconnected": "no net"
      },
      "tray": { "spacing": 8 }
    }
  '';

  # Dark bar, blue-accented launcher buttons with hover feedback.
  environment.etc."xdg/waybar/style.css".text = ''
    * {
      font-family: "DejaVu Sans", sans-serif;
      font-size: 14px;
      border: none;
      border-radius: 0;
    }
    window#waybar {
      background-color: #1f2330;
      color: #e6e8ee;
    }
    #custom-opencpn, #custom-xygrib, #custom-terminal,
    #custom-notes, #custom-browser, #custom-signalk {
      background-color: #2a2e3a;
      color: #ffffff;
      padding: 2px 12px;
      margin: 4px 2px;
      border-radius: 6px;
    }
    #custom-opencpn:hover, #custom-xygrib:hover, #custom-terminal:hover,
    #custom-notes:hover, #custom-browser:hover, #custom-signalk:hover {
      background-color: ${accent};
    }
    #clock { font-weight: bold; }
    #cpu, #memory, #network, #tray {
      padding: 0 10px;
      color: #b8bccb;
    }
  '';

  environment.systemPackages = [
    pkgs.labwc
    pkgs.waybar
    pkgs.swaybg
    pkgs.mako
    pkgs.libnotify
    pkgs.foot
    pkgs.xwayland
    pkgs.pcmanfm
    pkgs.xfce.mousepad
    pkgs.arc-theme
    pkgs.papirus-icon-theme
    pkgs.adwaita-icon-theme
    pkgs.font-awesome
    navBlueTheme
  ];

  # Autologin into labwc at boot; agreety covers a manual re-login.
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
}
