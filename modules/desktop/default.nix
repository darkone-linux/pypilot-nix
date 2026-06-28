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
  options,
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

  # config.txt exists only on the nixos-raspberrypi base (Pi hosts), not the
  # plain-nixpkgs lab VM. Gate the HDMI tweaks so the module stays evaluable.
  hasConfigTxt = options.hardware ? raspberry-pi;
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

    opencpnMaximize = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Maximize OpenCPN on launch (labwc window rule): it fills the screen below
        the top panel, like clicking the window's maximize button — not the F11
        full-screen mode. labwc only.
      '';
    };

    autostart = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "chromium --kiosk http://localhost:3000" ];
      description = "Extra shell commands appended to the session autostart.";
    };

    brightnessBus = mkOption {
      type = types.int;
      default = 20;

      # HDMI screens have no /sys backlight; brightness goes over DDC/CI (i2c).
      # Pinning the bus keeps ddcutil off the HAT's i2c-1. Pi 4: HDMI0=20, HDMI1=21.
      description = "i2c bus of the HDMI display for DDC/CI brightness (ddcutil --bus).";
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
          pkgs.gpsd
        ];

        hardware.graphics.enable = mkDefault true;
        fonts.packages = [ pkgs.dejavu_fonts ];

        # HDMI/onboard audio: PipeWire + the session user in `audio` so
        # wireplumber can open the ALSA cards (greetd autologin grants no
        # device ACLs, so the group membership is what unlocks them).
        services.pipewire = {
          enable = mkDefault true;
          alsa.enable = mkDefault true;
          pulse.enable = mkDefault true;

          # Prefer HDMI for output: bump any HDMI sink above the analog jack so
          # it becomes the default the volume keys and apps drive.
          wireplumber.extraConfig."51-hdmi-default" = {
            "monitor.alsa.rules" = [
              {
                matches = [ { "node.name" = "~alsa_output.*hdmi.*"; } ];
                actions.update-props."priority.session" = 2000;
              }
            ];
          };
        };
        security.rtkit.enable = mkDefault true;
        users.users.${cfg.user}.extraGroups = [ "audio" ];
      }

      # ---- robust HDMI bring-up (Pi, KMS) ----
      #
      # The vendor base sets disable_fw_kms_setup=1, so the firmware writes no
      # video= line and the kernel must probe the EDID at runtime. A monitor
      # plugged after boot, weak hotplug (HPD), or a flaky EDID/cable then leaves
      # the connector dark with no fallback — a black screen on the helm.
      #
      # Hand display setup back to the firmware: it reads the EDID at boot, passes
      # the native mode on the cmdline, and (force_hotplug) lights the output even
      # when HPD is low. Auto-detection kept, just made reliable.
      #
      # optionalAttrs, not mkIf: the option is undeclared on the lab VM. mkIf
      # only gates the value — it still emits the `hardware.raspberry-pi` path,
      # which fails the "option does not exist" check. optionalAttrs drops the
      # key entirely when absent.
      (lib.optionalAttrs hasConfigTxt {
        hardware.raspberry-pi.config.all.options = {

          # Re-enable firmware KMS setup (base default is 1 = disabled). Integer
          # 0, not boolean false: the renderer does toString, and `false` would
          # emit an empty `disable_fw_kms_setup=`.
          disable_fw_kms_setup = {
            enable = true;
            value = 0;
          };

          # Assume a display is attached even if HPD is not asserted.
          hdmi_force_hotplug = {
            enable = true;
            value = 1;
          };

          # Drive the port in HDMI mode (sound enabled), not DVI.
          hdmi_drive = {
            enable = true;
            value = 2;
          };
        };
      })

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
