# desktop/labwc.nix — minimal Wayland session, themed for the helm.
#
# Active only when `compositor == "labwc"`. Builds a polished single-screen
# appliance: solid blue background (swaybg), dark labwc window theme (NavBlue),
# Arc-Dark/Papirus for GTK apps. The waybar top panel has a start-menu button
# (nwg-drawer, full-screen flat app grid), quick-launch icon glyphs (with
# tooltips), and a window taskbar; the right-click root menu groups apps under
# Applications, PyPilot and Outils submenus with icons.
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
  pypilot = config.services.navigation.pypilot;
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
    opencpn = "${opencpn.finalPackage}/bin/opencpn";
    xygrib = "${pkgs.xygrib}/bin/xygrib";
    terminal = "${pkgs.foot}/bin/foot";
    notes = "${pkgs.featherpad}/bin/featherpad";
    browser = "${pkgs.chromium}/bin/chromium";
    signalk = "${pkgs.chromium}/bin/chromium --app=http://localhost:3000/";
    files = "${pkgs.pcmanfm}/bin/pcmanfm";
    pdf = "${pkgs.evince}/bin/evince";
    vlc = "${pkgs.vlc}/bin/vlc";

    # Tools: gpsd's GTK test client + a GTK3 calculator (follows Arc-Dark).
    xgps = "${pkgs.gpsd}/bin/xgps";
    calculator = "${pkgs.qalculate-gtk}/bin/qalculate-gtk";

    # Hardware scan: list serial nav devices + paste-ready Nix snippets, held
    # open in a terminal so the output can be read and copied.
    scanHw = ''${pkgs.foot}/bin/foot --title="Scan Matériel" ${pkgs.bash}/bin/bash -c "${pkgs.nav-discover}/bin/nav-discover; echo; read -n1 -rsp 'Appuyez sur une touche pour fermer...'"'';

    # PyPilot front-ends: three wx GUIs from the daemon package, plus its web UI
    # (served by pypilot_web on :8000) shown in a Chromium app window.
    pypilotControl = "${pypilot.package}/bin/pypilot_control";
    pypilotCalibration = "${pypilot.package}/bin/pypilot_calibration";
    pypilotClient = "${pypilot.package}/bin/pypilot_client_wx";
    pypilotWeb = "${pkgs.chromium}/bin/chromium --app=http://localhost:8000/";
  };

  # nwg-drawer: full-screen categorized app grid (the start menu). Run resident
  # at startup (-r), then a bare invocation toggles it open.
  nwgDrawer = "${pkgs.nwg-drawer}/bin/nwg-drawer";

  # Panel glyphs. Nix has no unicode escape, and literal PUA bytes get stripped,
  # so build each glyph from its codepoint via JSON's \u escape at eval time
  # (the .nix source stays ASCII). Codepoints are Font Awesome v4 (in the range
  # bundled by Symbols Nerd Font).
  faGlyph = code: builtins.fromJSON ''"\u${code}"'';
  glyph = {
    menu = faGlyph "f00a";
    terminal = faGlyph "f120";
    opencpn = faGlyph "f14e";
    grib = faGlyph "f0c2";
    signalk = faGlyph "f012";
    web = faGlyph "f0ac";
    editor = faGlyph "f044";
    moon = faGlyph "f186";
    sun = faGlyph "f185";
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
    pypilotControl = notify "pypilot-control" "PyPilot Control" bin.pypilotControl;
    pypilotCalibration = notify "pypilot-calibration" "PyPilot Calibration" bin.pypilotCalibration;
    pypilotClient = notify "pypilot-client" "PyPilot Client" bin.pypilotClient;
    pypilotWeb = notify "pypilot-web" "PyPilot Web" bin.pypilotWeb;
  };

  # Desktop-entry overrides that hide helper/dev launchers from the drawer grid.
  # A same-named entry placed earlier in XDG_DATA_DIRS wins nwg-drawer's de-dup
  # (first id seen) and carries NoDisplay=true, so the real entry stays hidden.
  hiddenAppIds = [
    "vim.desktop"
    "gvim.desktop"
    "nixos-manual.desktop"
    "foot-server.desktop"
    "footclient.desktop"
    "pcmanfm-desktop-pref.desktop"
  ];
  hiddenDesktops = pkgs.runCommand "nwg-hidden-desktops" { } ''
    mkdir -p "$out/share/applications"
    for id in ${concatStringsSep " " hiddenAppIds}; do
      printf '[Desktop Entry]\nType=Application\nNoDisplay=true\n' \
        > "$out/share/applications/$id"
    done
  '';

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
        "XDG_DATA_DIRS=${hiddenDesktops}/share:$XDG_DATA_DIRS ${nwgDrawer} -r -nocats -fm ${pkgs.pcmanfm}/bin/pcmanfm -term ${pkgs.foot}/bin/foot -is 64 -c 6 >/dev/null 2>&1 &"
      ]
      ++ optional (opencpn.enable && cfg.autostartOpencpn) "${bin.opencpn} &"
      ++ cfg.autostart
    )
    + "\n";

  # Session env: keyboard follows the system, cursor + GTK theme, and a dark Qt
  # style so Qt apps (XyGrib, FeatherPad) get visible, themed widgets.
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

        <!-- Icon theme for the right-click menu; app icons (opencpn, xygrib,
             chromium) fall back to hicolor. -->
        <icon>Papirus-Dark</icon>
        <cornerRadius>6</cornerRadius>
        <font name="sans" size="12" />
      </theme>
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

        <!-- Keep all default window bindings (<default/>); on the desktop (Root)
             disable the menu on left/middle click — an action-less mousebind
             overrides the default and is then cleared by labwc. Only right click
             still opens the minimal session menu. -->
        <default />
        <context name="Root">
          <mousebind button="Left" action="Press" />
          <mousebind button="Middle" action="Press" />
          <mousebind button="Right" action="Press">
            <action name="ShowMenu" menu="root-menu" />
          </mousebind>
        </context>
      </mouse>
      ${lib.optionalString cfg.opencpnMaximize ''
        <windowRules>

          <!-- OpenCPN maximized on map: fills the screen below the waybar panel
               (its reserved zone), like the maximize button. Match is on the
               XWayland WM_CLASS, case-insensitive. -->
          <windowRule identifier="opencpn">
            <action name="Maximize" />
          </windowRule>
        </windowRules>
      ''}
    </labwc_config>
  '';

  # Right-click menu: the top-left quick-launch apps under "Applications", the
  # autopilot front-ends under "PyPilot", utilities under "Outils", then session
  # actions. All-colour icon set: real app logos where they exist, otherwise a
  # related colourful icon from Papirus' apps/ set (never the mono action/device
  # glyphs) — keeps the menu visually uniform. Resolved via Papirus-Dark/hicolor.
  environment.etc."xdg/labwc/menu.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <openbox_menu>
      <menu id="root-menu" label="Menu">
        <menu id="apps-menu" label="Applications" icon="applications-other">
          <item label="OpenCPN" icon="opencpn"><action name="Execute"><command>${launch.opencpn}</command></action></item>
          <item label="XyGrib" icon="gnome-weather"><action name="Execute"><command>${launch.xygrib}</command></action></item>
          <item label="SignalK" icon="applications-internet"><action name="Execute"><command>${launch.signalk}</command></action></item>
          <item label="Navigateur" icon="chromium"><action name="Execute"><command>${launch.browser}</command></action></item>
          <item label="Éditeur" icon="featherpad"><action name="Execute"><command>${bin.notes}</command></action></item>
        </menu>
        <menu id="pypilot-menu" label="PyPilot" icon="marble">
          <item label="Control" icon="preferences-system"><action name="Execute"><command>${launch.pypilotControl}</command></action></item>
          <item label="Calibration" icon="applications-science"><action name="Execute"><command>${launch.pypilotCalibration}</command></action></item>
          <item label="Client" icon="utilities-system-monitor"><action name="Execute"><command>${launch.pypilotClient}</command></action></item>
          <item label="Web" icon="web-browser"><action name="Execute"><command>${launch.pypilotWeb}</command></action></item>
        </menu>
        <menu id="tools-menu" label="Outils" icon="applications-utilities">
          <item label="xgps" icon="org.gnome.Maps"><action name="Execute"><command>${bin.xgps}</command></action></item>
          <item label="Calculatrice" icon="qalculate"><action name="Execute"><command>${bin.calculator}</command></action></item>
          <item label="Scan Matériel" icon="utilities-terminal"><action name="Execute"><command>${bin.scanHw}</command></action></item>
          <item label="Recharger labwc" icon="system-restart"><action name="Reconfigure" /></item>
        </menu>
        <separator />

        <!-- logind allows reboot/poweroff for the active local session (polkit). -->
        <item label="Redémarrer" icon="system-reboot"><action name="Execute"><command>${pkgs.systemd}/bin/systemctl reboot</command></action></item>
        <item label="Éteindre" icon="system-shutdown"><action name="Execute"><command>${pkgs.systemd}/bin/systemctl poweroff</command></action></item>
      </menu>
    </openbox_menu>
  '';

  # GTK apps (pcmanfm) follow the same dark look.
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Arc-Dark
    gtk-icon-theme-name=Papirus-Dark
    gtk-font-name=Sans 12
    gtk-cursor-theme-name=Adwaita
    gtk-cursor-theme-size=24
  '';

  # FeatherPad (Qt) defaults: shipped as a system-wide QSettings fallback that the
  # editor reads when the user has no ~/.config/featherpad/fp.conf yet.
  # - font: legacy 10-field QFont string (Qt6 reads it) → JetBrains Mono 16.
  # - darkColorScheme: dark editor area (chrome follows the Qt Adwaita-Dark style).
  # - textMargin: a little padding around the text; textTabSize: 2-space indent.
  # Syntax highlighting is on by default; line numbers off by default.
  # Chrome kept minimal: no toolbar (thin menubar stays — FeatherPad forbids hiding
  # both), search bar appears only on Ctrl+F, tab bar only with several tabs.
  environment.etc."xdg/featherpad/fp.conf".text = ''
    [text]
    font="JetBrainsMono Nerd Font Mono,16,-1,5,50,0,0,0,0,0"
    darkColorScheme=true
    textMargin=true
    textTabSize=2

    [window]
    noMenubar=true
    hideSearchbar=true
    hideSingleTab=true
    showStatusbar=false
  '';

  # Large, readable terminal font — the default was unusably small on the helm.
  # Open roomy too (~3x the default area on the 1080p helm display).
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=JetBrainsMono Nerd Font Mono:size=18
    pad=8x8
    initial-window-size-pixels=1500x960

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
        "custom/menu", "custom/terminal", "custom/opencpn", "custom/xygrib",
        "custom/signalk", "custom/browser", "custom/notes", "wlr/taskbar"
      ],
      "modules-center": [ "clock" ],
      "modules-right": [ "custom/bright-down", "custom/bright-up", "cpu", "memory", "temperature", "network", "tray" ],
      "custom/menu":     { "format": "${glyph.menu}",    "on-click": "${nwgDrawer}",       "tooltip": true, "tooltip-format": "Applications" },
      "custom/terminal": { "format": "${glyph.terminal}", "on-click": "${launch.terminal}", "tooltip": true, "tooltip-format": "Terminal" },
      "custom/opencpn":  { "format": "${glyph.opencpn}", "on-click": "${launch.opencpn}",  "tooltip": true, "tooltip-format": "OpenCPN" },
      "custom/xygrib":   { "format": "${glyph.grib}",    "on-click": "${launch.xygrib}",   "tooltip": true, "tooltip-format": "XyGrib" },
      "custom/signalk":  { "format": "${glyph.signalk}", "on-click": "${launch.signalk}",  "tooltip": true, "tooltip-format": "SignalK" },
      "custom/browser":  { "format": "${glyph.web}",     "on-click": "${launch.browser}",  "tooltip": true, "tooltip-format": "Navigateur" },
      "custom/notes":    { "format": "${glyph.editor}",  "on-click": "${bin.notes}",       "tooltip": true, "tooltip-format": "Éditeur" },
      "wlr/taskbar": {
        "icon-size": 24,
        "on-click": "activate",
        "on-click-middle": "close",
        "tooltip-format": "{title}"
      },
      "custom/bright-down": { "format": "${glyph.moon}", "on-click": "${brightness "down"}", "tooltip": true, "tooltip-format": "Luminosité −" },
      "custom/bright-up":   { "format": "${glyph.sun}",  "on-click": "${brightness "up"}",   "tooltip": true, "tooltip-format": "Luminosité +" },
      "clock":   { "format": "{:%a %d %b  %H:%M}" },
      "cpu":     { "format": "CPU {usage}%", "interval": 5 },
      "memory":  { "format": "RAM {percentage}%", "interval": 5 },

      "temperature": { "thermal-zone": 0, "format": "T° {temperatureC}°C", "interval": 5 },
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
    #custom-menu, #custom-terminal, #custom-opencpn, #custom-xygrib,
    #custom-signalk, #custom-browser, #custom-notes {
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
    #custom-menu:hover, #custom-terminal:hover, #custom-opencpn:hover, #custom-xygrib:hover,
    #custom-signalk:hover, #custom-browser:hover, #custom-notes:hover {
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
    #cpu, #memory, #temperature, #network, #tray {
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
    pkgs.featherpad
    pkgs.qalculate-gtk
    pkgs.adwaita-qt6
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

  # Symbols-only feeds the panel glyphs; JetBrains Mono is the editor/terminal font.
  fonts.packages = [
    pkgs.nerd-fonts.symbols-only
    pkgs.nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig.enable = true;

  # JetBrains Mono becomes the default monospace (FeatherPad, foot). It is also
  # FeatherPad's fallback: a bare QFont("Monospace") resolves here via fontconfig.
  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font Mono" ];

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
