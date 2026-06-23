# development.nix — on-box developer & admin toolbox.
#
# Stay autonomous on the boat box without a workstation: the Zed editor plus
# curated essentials, system/network admin and Nix-project tooling. Groups
# toggle independently and all default on, so a bare `enable` gives the full
# kit. Lean by design — no heavy desktop suites — and each group is gated by
# `lib.optionals` so a disabled group pulls nothing into the closure.
#
# Graphical bits (Zed) only make sense where a desktop session runs; disable
# `editor` on headless hosts.

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
      description = "Zed graphical editor (only useful with a desktop session).";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages =

      # Graphical editor (binary: zeditor).
      optionals cfg.editor [ pkgs.zed-editor ]

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
      );
  };
}
