# development.nix — on-box developer & admin toolbox.
#
# Stay autonomous on the boat box without a workstation: editors (Helix +
# Geany), curated essentials, system/network admin, Nix-project tooling and the
# on-board marine diagnostics (GPS/NMEA, CAN, SDR, GPIO — the OpenPlotter
# toolbox equivalent). Groups toggle independently and all default on, so a bare
# `enable` gives the full kit. Lean by design — no heavy desktop suites — and
# each group is gated by `lib.optionals` so a disabled group pulls nothing in.
#
# Helix is a terminal editor (headless-friendly); Geany is graphical and only
# useful where a desktop session runs. Disable `editor` to drop both.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation.development;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    optionals
    types
    ;

  # Full-dark editor colour scheme (VS Code "Dark+" palette). Geany applies the
  # chrome styles (default/selection/current line/margins) globally and maps the
  # syntax names per filetype; unknown names are ignored harmlessly.
  geanyDarkScheme = pkgs.writeText "pypilot-dark.conf" ''
    [theme_info]
    name=Pypilot Dark
    description=Full-dark scheme for the on-box Geany
    version=1.0
    author=pypilot-nix

    [named_colors]
    bg=#1e1e1e
    bg_alt=#252526
    fg=#d4d4d4
    sel_bg=#264f78
    line_bg=#2a2d2e
    margin_fg=#858585
    comment=#6a9955
    keyword=#569cd6
    type=#4ec9b0
    function=#dcdcaa
    string=#ce9178
    number=#b5cea8
    preproc=#c586c0
    ident=#9cdcfe
    constant=#4fc1ff
    error=#f44747
    cursor=#aeafad
    whitespace=#3b3b3b

    [named_styles]

    # Editor chrome (applied for every filetype)
    default=fg;bg;false;false
    selection=;sel_bg;false;true
    current_line=;line_bg;true
    brace_good=keyword;;true
    brace_bad=error;;true
    margin_line_number=margin_fg;bg
    margin_folding=margin_fg;bg
    indent_guide=whitespace
    caret=cursor;;false
    marker_search=;sel_bg
    call_tips=fg;bg_alt
    white_space=whitespace;;true

    # Syntax
    comment=comment;;false;true
    comment_doc=comment;;false;true
    comment_line=comment;;false;true
    comment_line_doc=comment;;false;true
    number=number
    number_1=number
    number_2=number
    type=type;;true
    class=type;;true
    function=function
    parameter=ident
    keyword=keyword;;true
    keyword_1=keyword;;true
    keyword_2=type;;true
    keyword_3=preproc
    keyword_4=preproc
    string=string
    string_1=string
    string_2=string
    string_eol=string;;false;true
    character=string
    backticks=string
    here_doc=string
    scharacter=string
    preprocessor=preproc
    pragma=preproc
    operator=fg
    identifier=fg
    identifier_1=fg
    identifier_2=ident
    decorator=preproc
    error=error;;false;true
    regex=string
    label=preproc;;true
    tag=keyword
    attribute=function
    value=string
    entity=constant
    namespace=type;;true
    variable=ident
  '';

  # Seeded once so user edits persist; the scheme is always refreshed.
  geanyDarkConf = pkgs.writeText "geany.conf" ''
    [geany]
    color_scheme=pypilot-dark.conf
  '';

  # Materialise the dark config in the user's XDG dir on launch (store files are
  # read-only, hence `install -m644` to land writable copies Geany can rewrite).
  geanySeed = pkgs.writeShellScript "geany-seed-dark" ''
    cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/geany"
    ${pkgs.coreutils}/bin/mkdir -p "$cfg/colorschemes"

    [ -e "$cfg/geany.conf" ] || ${pkgs.coreutils}/bin/install -m644 ${geanyDarkConf} "$cfg/geany.conf"
    ${pkgs.coreutils}/bin/install -m644 ${geanyDarkScheme} "$cfg/colorschemes/pypilot-dark.conf"
  '';

  # Geany wrapped to force dark GTK chrome and seed the dark scheme. symlinkJoin
  # keeps the upstream .desktop entry and icons; wrapProgram replaces bin/geany.
  geanyDark = pkgs.symlinkJoin {
    name = "geany-dark";
    paths = [ pkgs.geany ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/geany \
        --set GTK_THEME Adwaita:dark \
        --run ${geanySeed}
    '';
  };
in
{
  options.services.navigation.development = {
    enable = mkEnableOption "the on-box developer and admin toolbox";

    essentials = mkOption {
      type = types.bool;
      default = true;
      description = "Frequently used shell helpers (archives, fetch, monitors).";
    };

    admin = mkOption {
      type = types.bool;
      default = true;
      description = "System, network and hardware-bench diagnostics tools.";
    };

    nixAdmin = mkOption {
      type = types.bool;
      default = true;
      description = "Nix project tooling backing the Justfile (fmt, lint, build).";
    };

    editor = mkOption {
      type = types.bool;
      default = true;
      description = "Editors: Helix (terminal) and a dark-themed Geany (graphical).";
    };

    marine = mkOption {
      type = types.bool;
      default = true;
      description = "On-board diagnostics: GPS/NMEA, CAN/NMEA2000, network, SDR, GPIO.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages =

      # Editors: Helix (terminal, hx) + dark-themed Geany (graphical).
      optionals cfg.editor [
        pkgs.helix
        geanyDark
      ]

      # Day-to-day shell helpers.
      ++ optionals cfg.essentials (
        with pkgs;
        [
          btop # Resource monitor
          cpufetch # CPU info
          duf # Disk usage / free, friendlier df
          fd # Fast find, used by editors/search
          gawk
          jq # Inspect SignalK JSON streams
          less
          microfetch # Tiny fastfetch
          rename
          ripgrep # Fast recursive grep
          rsync
          tree
          unzip
          wget
          wipe # Secure file erase
          zip
        ]
      )

      # System, network and hardware-bench diagnostics.
      ++ optionals cfg.admin (
        with pkgs;
        [
          ccrypt
          dig
          dos2unix
          i2c-tools # i2cdetect — probe HAT sensors on i2c-1
          inetutils
          iptraf-ng
          iw
          libargon2 # argon2
          lsof
          nettools
          nmap
          pciutils # lspci, setpci
          picocom # Lightweight serial console for NMEA / pypilot UART
          psmisc # killall, pstree, fuser
          rmlint
          socat # Bridge/inspect serial & TCP NMEA streams
          strace
          tcpdump
          usbutils # lsusb — enumerate USB GPS / serial adapters
          wirelesstools # iwconfig, iwlist
        ]
      )

      # Nix project tooling — same set backing the dev shell / Justfile recipes.
      ++ optionals cfg.nixAdmin (
        with pkgs;
        [
          deadnix
          git
          just
          nil # Nix LSP for the editor
          nix-output-monitor # nom
          nixfmt
          statix
          treefmt
        ]
      )

      # On-board navigation diagnostics (the OpenPlotter toolbox equivalent).
      ++ optionals cfg.marine (
        with pkgs;
        [

          # GPS / NMEA — gpsd clients (cgps, gpsmon, gpspipe, gpsdecode).
          gpsd
          canboat # NMEA2000 analyzer / converter (analyzer, n2kd)

          # CAN / NMEA2000 — available on every host, not just the MacArthur HAT.
          can-utils # candump, cansniffer, canbusload, slcand

          # Network (complements nmap/tcpdump/iw already in admin).
          ethtool
          mtr # traceroute + ping
          iperf3 # throughput testing

          # SDR / radio. Blog fork for RTL-SDR v4 (R828D) support; rtl_biast
          # drives the bias-tee that powers an active AIS antenna.
          rtl-sdr-blog # rtl_test, rtl_biast, rtl_eeprom, rtl_fm, rtl_power
          ais-catcher # AIS decoder CLI (AIS-catcher -d:0 -v to diagnose)
          multimon-ng # decode POCSAG / AFSK / AIS audio

          # GPIO.
          libgpiod # gpioget, gpioset, gpiomon, gpiodetect
        ]
      );
  };
}
