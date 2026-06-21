# desktop/labwc.nix — minimal Wayland session, themed for the helm.
#
# Active only when `compositor == "labwc"`. Builds a polished single-screen
# appliance: solid blue background (swaybg), dark labwc window theme (NavBlue),
# Arc-Dark/Papirus for GTK apps. The waybar top panel has a start-menu button
# (nwg-drawer, full-screen categorized app grid), quick-launch icon glyphs, and
# a window taskbar; the right-click root menu lists apps by category with icons.
# Slow apps (OpenCPN, browser) pop a "starting…" notification (mako) so the
# helmsman doesn't click twice. Media keys + waybar buttons drive screen
# brightness over DDC/CI (ddcutil) and volume via PipeWire (wpctl) — brightness
# matters for day/night navigation.

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

  # nwg-drawer: full-screen categorized app grid (the start menu). Run resident
  # at startup (-r), then a bare invocation toggles it open.
  nwgDrawer = "${pkgs.nwg-drawer}/bin/nwg-drawer";

  # Panel glyphs from Font Awesome v4 range (safe in Symbols Nerd Font).
  glyph = {
    menu = "";
    opencpn = "";
    grib = "";
    signalk = "";
    web = "";
    sun = "";
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

  # Brightness over DDC/CI (no /sys backlight on HDMI). Bus is pinned so ddcutil
  # never probes the HAT's i2c-1; each press nudges VCP 0x10 and shows the value.
  brightness =
    dir:
    "${pkgs.writeShellScript "brightness-${dir}" ''
      bus=${toString cfg.brightnessBus}
      ${pkgs.ddcutil}/bin/ddcutil --bus "$bus" --noverify setvcp 10 ${if dir == "up" then "+" else "-"} 10
      val=$(${pkgs.ddcutil}/bin/ddcutil --bus "$bus" --brief getvcp 10 | ${pkgs.gawk}/bin/awk '{print $4}')
      ${pkgs.libnotify}/bin/notify-send -t 1500 "Luminosité" "''${val}%" || true
    ''}";

  # Volume via PipeWire's wpctl (capped at 100%). Works once a sink exists.
  wpctl = "${pkgs.wireplumber}/bin/wpctl";
  vol = {
    up = "${wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
    down = "${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-";
    mute = "${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
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

  # Desktop entry so the chromium-app SignalK shows up (icon + category) in the
  # drawer and the right-click menu like a real application.
  signalkDesktop = pkgs.writeTextDir "share/applications/signalk.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=SignalK
    Comment=Tableau de bord SignalK
    Exec=${bin.signalk}
    Icon=network-server
    Terminal=false
    Categories=Network;
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
        "${nwgDrawer} -r -fm ${pkgs.pcmanfm}/bin/pcmanfm -term ${pkgs.foot}/bin/foot -is 64 -c 6 >/dev/null 2>&1 &"
      ]
      ++ optional (opencpn.enable && cfg.autostartOpencpn) "${bin.opencpn} &"
      ++ cfg.autostart
    )
    + "\n";

  # Session env: keyboard follows the system, cursor + GTK theme, and a dark Qt
  # style so Qt apps (XyGrib) get visible, themed widgets instead of blank ones.
  environment.etc."xdg/labwc/environment".text = ''
    XKB_DEFAULT_LAYOUT=${config.services.xserver.xkb.layout}
    XCURSOR_THEME=Adwaita
    XCURSOR_SIZE=24
    GTK_THEME=Arc-Dark
    QT_STYLE_OVERRIDE=Adwaita-Dark
  '';

  # labwc core config: NavBlue theme + a <keyboard> section. Declaring any
  # keybind disables labwc's built-in keyboard defaults, so we re-list the useful
  # ones (window cycle, close, maximize, snap, client menu) next to the custom
  # Ctrl+Alt launchers. We still declare NO <mouse> section, so default mouse
  # bindings (drag-move, title-bar buttons, right-click root menu) stay intact.
  environment.etc."xdg/labwc/rc.xml".text = ''
    <?xml version="1.0"?>
    <labwc_config>
      <theme>
        <name>NavBlue</name>
        <cornerRadius>6</cornerRadius>
        <font name="sans" size="12" />
      </theme>

      <!-- Show application icons next to the right-click menu entries. -->
      <menu>
        <showIcons>yes</showIcons>
      </menu>
      <keyboard>

        <!-- labwc defaults worth keeping (lost the moment any keybind is set). -->
        <keybind key="A-Tab"><action name="NextWindow" /></keybind>
        <keybind key="A-S-Tab"><action name="PreviousWindow" /></keybind>
        <keybind key="A-F4"><action name="Close" /></keybind>
        <keybind key="W-a"><action name="ToggleMaximize" /></keybind>
        <keybind key="W-Left"><action name="SnapToEdge" direction="left" combine="yes" /></keybind>
        <keybind key="W-Right"><action name="SnapToEdge" direction="right" combine="yes" /></keybind>
        <keybind key="W-Up"><action name="SnapToEdge" direction="up" combine="yes" /></keybind>
        <keybind key="W-Down"><action name="SnapToEdge" direction="down" combine="yes" /></keybind>
        <keybind key="A-Space"><action name="ShowMenu" menu="client-menu" atCursor="no" /></keybind>

        <!-- Super+Space opens the start menu (nwg-drawer). -->
        <keybind key="W-space"><action name="Execute"><command>${nwgDrawer}</command></action></keybind>

        <!-- Custom Ctrl+Alt launchers (slow apps reuse the notify wrappers). -->
        <keybind key="C-A-t"><action name="Execute"><command>${bin.terminal}</command></action></keybind>
        <keybind key="C-A-o"><action name="Execute"><command>${launch.opencpn}</command></action></keybind>
        <keybind key="C-A-g"><action name="Execute"><command>${launch.xygrib}</command></action></keybind>
        <keybind key="C-A-n"><action name="Execute"><command>${bin.notes}</command></action></keybind>
        <keybind key="C-A-w"><action name="Execute"><command>${launch.browser}</command></action></keybind>
        <keybind key="C-A-s"><action name="Execute"><command>${launch.signalk}</command></action></keybind>

        <!-- Brightness (DDC/CI) and volume (PipeWire) media keys. -->
        <keybind key="XF86_MonBrightnessUp"><action name="Execute"><command>${brightness "up"}</command></action></keybind>
        <keybind key="XF86_MonBrightnessDown"><action name="Execute"><command>${brightness "down"}</command></action></keybind>
        <keybind key="XF86_AudioRaiseVolume"><action name="Execute"><command>${vol.up}</command></action></keybind>
        <keybind key="XF86_AudioLowerVolume"><action name="Execute"><command>${vol.down}</command></action></keybind>
        <keybind key="XF86_AudioMute"><action name="Execute"><command>${vol.mute}</command></action></keybind>
      </keyboard>

      <mouse>

        <!-- Keep every default mouse binding, then narrow the desktop: only a
             RIGHT click opens the menu (default also bound it to left/middle). -->
        <default />
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
        <menu id="menu-nav" label="Navigation" icon="applications-internet">
          <item label="OpenCPN" icon="opencpn"><action name="Execute"><command>${launch.opencpn}</command></action></item>
          <item label="GRIB (XyGrib)" icon="xygrib"><action name="Execute"><command>${launch.xygrib}</command></action></item>
          <item label="SignalK" icon="network-server"><action name="Execute"><command>${launch.signalk}</command></action></item>
        </menu>
        <menu id="menu-net" label="Internet" icon="web-browser">
          <item label="Navigateur web" icon="web-browser"><action name="Execute"><command>${launch.browser}</command></action></item>
        </menu>
        <menu id="menu-media" label="Multimédia" icon="applications-multimedia">
          <item label="Lecteur VLC" icon="vlc"><action name="Execute"><command>${launch.vlc}</command></action></item>
          <item label="Visionneuse PDF" icon="application-pdf"><action name="Execute"><command>${launch.pdf}</command></action></item>
        </menu>
        <menu id="menu-tools" label="Outils" icon="applications-utilities">
          <item label="Terminal" icon="utilities-terminal"><action name="Execute"><command>${launch.terminal}</command></action></item>
          <item label="Notes" icon="accessories-text-editor"><action name="Execute"><command>${launch.notes}</command></action></item>
          <item label="Fichiers" icon="system-file-manager"><action name="Execute"><command>${launch.files}</command></action></item>
        </menu>
        <separator />
        <item label="Recharger labwc" icon="view-refresh"><action name="Reconfigure" /></item>
        <item label="Quitter la session" icon="system-log-out"><action name="Exit" /></item>
      </menu>
    </openbox_menu>
  '';

  # GTK apps (pcmanfm, mousepad, xygrib) follow the same dark look.
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Arc-Dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-font-name=Sans 12
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

  # Top panel: start menu + quick-launch icons + window list (left), clock
  # (center), brightness + system (right). The full app set lives in the drawer
  # and the right-click menu, so the bar stays uncluttered.
  environment.etc."xdg/waybar/config".text = ''
    {
      "layer": "top",
      "position": "top",
      "height": 40,
      "spacing": 4,
      "modules-left": [
        "custom/menu", "custom/opencpn", "custom/xygrib",
        "custom/signalk", "custom/browser", "wlr/taskbar"
      ],
      "modules-center": [ "clock" ],
      "modules-right": [ "custom/bright-down", "custom/bright-up", "cpu", "memory", "network", "tray" ],
      "custom/menu":     { "format": "${glyph.menu}",    "on-click": "${nwgDrawer}",       "tooltip": false },
      "custom/opencpn":  { "format": "${glyph.opencpn}", "on-click": "${launch.opencpn}",  "tooltip": false },
      "custom/xygrib":   { "format": "${glyph.grib}",    "on-click": "${launch.xygrib}",   "tooltip": false },
      "custom/signalk":  { "format": "${glyph.signalk}", "on-click": "${launch.signalk}",  "tooltip": false },
      "custom/browser":  { "format": "${glyph.web}",     "on-click": "${launch.browser}",  "tooltip": false },
      "wlr/taskbar": {
        "icon-size": 24,
        "on-click": "activate",
        "on-click-middle": "close",
        "tooltip-format": "{title}"
      },
      "custom/bright-down": { "format": "${glyph.sun} −", "on-click": "${brightness "down"}", "tooltip": false },
      "custom/bright-up":   { "format": "${glyph.sun} +", "on-click": "${brightness "up"}",   "tooltip": false },
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

  # Dark bar with icon glyphs (Nerd Font), accent hover, and a window taskbar.
  environment.etc."xdg/waybar/style.css".text = ''
    * {
      font-family: "Symbols Nerd Font", "DejaVu Sans", sans-serif;
      font-size: 14px;
      border: none;
      border-radius: 0;
    }
    window#waybar {
      background-color: #1f2330;
      color: #e6e8ee;
    }
    #custom-menu, #custom-opencpn, #custom-xygrib,
    #custom-signalk, #custom-browser {
      font-size: 18px;
      background-color: #2a2e3a;
      color: #ffffff;
      padding: 0 12px;
      margin: 4px 2px;
      border-radius: 6px;
    }
    #custom-menu {
      background-color: ${accent};
    }
    #custom-menu:hover, #custom-opencpn:hover, #custom-xygrib:hover,
    #custom-signalk:hover, #custom-browser:hover {
      background-color: ${blue};
    }
    #taskbar button {
      padding: 0 6px;
      margin: 3px 1px;
      border-radius: 6px;
    }
    #taskbar button.active {
      background-color: ${accent};
    }
    #custom-bright-down, #custom-bright-up {
      background-color: #2a2e3a;
      color: #ffffff;
      padding: 0 10px;
      margin: 4px 2px;
      border-radius: 6px;
    }
    #custom-bright-down:hover, #custom-bright-up:hover {
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
    pkgs.nwg-drawer
    pkgs.arc-theme
    pkgs.papirus-icon-theme
    pkgs.adwaita-icon-theme
    pkgs.adwaita-qt
    pkgs.font-awesome
    pkgs.ddcutil
    pkgs.wireplumber
    pkgs.gawk
    navBlueTheme
    signalkDesktop
  ];

  # Nerd Font symbols supply the panel glyphs (start, compass, cloud, …).
  fonts.packages = [ pkgs.nerd-fonts.symbols-only ];

  # DDC/CI brightness needs unprivileged i2c access: the i2c group + udev rules
  # from hardware.i2c, with the session user added to that group.
  hardware.i2c.enable = lib.mkDefault true;
  users.users.${cfg.user}.extraGroups = [ "i2c" ];

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
