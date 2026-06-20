# desktop/labwc.nix — minimal Wayland session, themed for the helm.
#
# Active only when `compositor == "labwc"`. Builds a polished single-screen
# appliance: solid blue background (swaybg), dark labwc window theme (NavBlue),
# Arc-Dark/Papirus for GTK apps, and a waybar top panel whose left side is a row
# of launcher buttons (OpenCPN, GRIB, terminal, notes, browser, Signal K). No
# right-click root menu — the panel is the only launcher (per design).

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

  blue = "#3C4FA2";

  # Launcher commands, full store paths (waybar inherits no PATH).
  cmd = {
    opencpn = "${opencpn.package}/bin/opencpn";
    xygrib = "${pkgs.xygrib}/bin/xygrib";
    terminal = "${pkgs.foot}/bin/foot";
    notes = "${pkgs.xfce.mousepad}/bin/mousepad";
    browser = "${pkgs.chromium}/bin/chromium";
    signalk = "${pkgs.chromium}/bin/chromium --app=https://localhost:3000/";
  };

  # labwc window decorations: dark with the blue accent on the active title.
  navBlueTheme = pkgs.writeTextDir "share/themes/NavBlue/labwc/themerc" ''
    border.width: 2
    padding.height: 4
    window.active.border.color: ${blue}
    window.inactive.border.color: #2a2e3a
    window.active.title.bg.color: ${blue}
    window.inactive.title.bg.color: #2a2e3a
    window.active.label.text.color: #ffffff
    window.inactive.label.text.color: #b0b4c0
    window.active.button.unpressed.image.color: #ffffff
    window.inactive.button.unpressed.image.color: #b0b4c0
    menu.items.bg.color: #1f2330
    menu.items.text.color: #e6e8ee
    menu.items.active.bg.color: ${blue}
    menu.items.active.text.color: #ffffff
    osd.bg.color: #1f2330
    osd.border.color: ${blue}
    osd.label.text.color: #e6e8ee
  '';
in
mkIf (cfg.enable && cfg.compositor == "labwc") {
  # Solid blue background + panel; OpenCPN only when explicitly requested.
  environment.etc."xdg/labwc/autostart".text =
    concatStringsSep "\n" (
      [
        "${pkgs.swaybg}/bin/swaybg -c '${blue}' >/dev/null 2>&1 &"
        "${pkgs.waybar}/bin/waybar >/dev/null 2>&1 &"
      ]
      ++ optional (opencpn.enable && cfg.autostartOpencpn) "${cmd.opencpn} &"
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

  # labwc core config: NavBlue theme, rounded corners, Super+Return = terminal.
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
          <action name="Execute" command="${cmd.terminal}" />
        </keybind>
      </keyboard>
    </labwc_config>
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
      "custom/opencpn":  { "format": "OpenCPN",  "on-click": "${cmd.opencpn}",  "tooltip": false },
      "custom/xygrib":   { "format": "GRIB",     "on-click": "${cmd.xygrib}",   "tooltip": false },
      "custom/terminal": { "format": "Terminal", "on-click": "${cmd.terminal}", "tooltip": false },
      "custom/notes":    { "format": "Notes",    "on-click": "${cmd.notes}",    "tooltip": false },
      "custom/browser":  { "format": "Web",      "on-click": "${cmd.browser}",  "tooltip": false },
      "custom/signalk":  { "format": "Signal K", "on-click": "${cmd.signalk}",  "tooltip": false },
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
      background-color: ${blue};
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
