# navigation.nix — top-level orchestrator for the marine navigation stack.
#
# Single entry point: importing this module and setting
# `services.navigation.enable = true` pulls in the hardware buses, the
# pypilot/signalk/opencpn services and the GPS/AIS plumbing (udev hotplug +
# gpsd). The individual services are still toggled via their own `enable`
# options.
#
# The custom packages (pkgs.pypilot, …) come from the flake overlay, applied by
# hosts/common.nix — or by the consumer when importing this module standalone.
# (A module must not set nixpkgs.overlays itself: it breaks pinned-pkgs setups
# such as the NixOS test framework.)

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.navigation;
  aiscfg = cfg.ais;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    optional
    optionals
    types
    concatStringsSep
    ;

  # A USB vendor/product pair used to match a serial device in udev.
  usbId = types.submodule {
    options = {
      vendorId = mkOption {
        type = types.str;
        example = "1546";
        description = "USB idVendor (hex, lowercase).";
      };
      productId = mkOption {
        type = types.str;
        example = "01a7";
        description = "USB idProduct (hex, lowercase).";
      };
    };
  };

  gpsName = lib.removePrefix "/dev/" cfg.gps.device;
  aisName = lib.removePrefix "/dev/" aiscfg.device;

  hasGpsIds = cfg.gps.vendorId != null && cfg.gps.productId != null;
  hasMotorIds = cfg.motor.vendorId != null && cfg.motor.productId != null;

  gpsAutodetect = cfg.gps.enable && cfg.gps.autodetect;
  aisAutodetect = aiscfg.enable && aiscfg.autodetect;
  aisSdr = aiscfg.enable && aiscfg.sdr.enable;

  # GNSS receivers hotplugged into gpsd: the curated list plus an explicit pin.
  gpsHotplugIds =
    cfg.gps.autodetectIds ++ optional hasGpsIds { inherit (cfg.gps) vendorId productId; };

  # udev: pin a USB serial device to a stable, dialout-readable /dev symlink.
  ttySymlink =
    {
      vendorId,
      productId,
      name,
    }:
    ''SUBSYSTEM=="tty", ATTRS{idVendor}=="${vendorId}", ATTRS{idProduct}=="${productId}", SYMLINK+="${name}", GROUP="dialout", MODE="0660", TAG+="systemd"'';

  # udev: hand a freshly plugged GNSS device to the running gpsd (hotplug).
  gpsHotplugRule =
    { vendorId, productId }:
    ''SUBSYSTEM=="tty", ACTION=="add", ATTRS{idVendor}=="${vendorId}", ATTRS{idProduct}=="${productId}", SYMLINK+="${gpsName}", GROUP="dialout", TAG+="systemd", ENV{SYSTEMD_WANTS}+="gpsdctl@%k.service"'';
in
{
  imports = [
    ./hardware
    ./pypilot.nix
    ./signalk.nix
    ./opencpn.nix
    ./gps-time.nix
    ./desktop.nix
  ];

  options.services.navigation = {
    enable = mkEnableOption "the declarative marine navigation stack";

    gps = {
      enable = mkEnableOption "the GPS receiver served by gpsd";

      device = mkOption {
        type = types.str;
        default = "/dev/gps0";
        description = "Device gpsd reads from in pinned mode; matches the udev symlink when USB IDs are set.";
      };

      autodetect = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Hotplug known USB GNSS receivers into gpsd (plug-and-play): gpsd starts
          empty and udev hands it each matching device as it appears. Disable to
          use the single pinned `device` instead.
        '';
      };

      autodetectIds = mkOption {
        type = types.listOf usbId;
        default = [
          # u-blox 5–9 (cdc_acm) — the common marine GPS pucks.
          {
            vendorId = "1546";
            productId = "01a5";
          }
          {
            vendorId = "1546";
            productId = "01a6";
          }
          {
            vendorId = "1546";
            productId = "01a7";
          }
          {
            vendorId = "1546";
            productId = "01a8";
          }
          {
            vendorId = "1546";
            productId = "01a9";
          }

          # Garmin GPS 18x, MediaTek/Holux, DeLorme — unambiguous GNSS IDs.
          {
            vendorId = "091e";
            productId = "0003";
          }
          {
            vendorId = "0e8d";
            productId = "3329";
          }
          {
            vendorId = "1163";
            productId = "0100";
          }
          {
            vendorId = "1163";
            productId = "0200";
          }
        ];
        description = ''
          USB IDs treated as GNSS receivers when `autodetect` is on. Defaults to
          receivers with a dedicated USB ID; generic serial chips (FTDI, CP210x,
          PL2303) are left out on purpose — they are also used by AIS and other
          gear, so add them here only if your GPS uses one.
        '';
      };

      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "1546";
        description = "USB idVendor pinning a specific GPS. Also added to the hotplug set when `autodetect` is on.";
      };

      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "01a7";
        description = "USB idProduct for the pinned GPS.";
      };
    };

    ais = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Feed an AIS / NMEA0183 receiver into Signal K.";
      };

      device = mkOption {
        type = types.str;
        default = "/dev/ttyOP_ais";
        description = "Stable /dev name the Signal K AIS serial provider reads.";
      };

      baudrate = mkOption {
        type = types.ints.positive;
        default = 38400;
        description = "AIS serial baud rate (NMEA0183 AIS is 38400).";
      };

      autodetect = mkOption {
        type = types.bool;
        default = true;
        description = "Symlink known USB AIS receivers to `device` on plug-in (plug-and-play).";
      };

      autodetectIds = mkOption {
        type = types.listOf usbId;
        default = [
          # Bench AIS receiver (OpenPlotter reference); extend per hardware.
          {
            vendorId = "27c5";
            productId = "0402";
          }
        ];
        description = ''
          USB IDs symlinked to `device` when `autodetect` is on. AIS receivers
          often share generic serial chips with other gear, so the list is
          explicit rather than class-based to avoid grabbing the wrong device.
        '';
      };

      sdr = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Read SDR-decoded AIS (ais-catcher) over UDP; needs the SDR stack (phase 6c).";
        };

        udpPort = mkOption {
          type = types.port;
          default = 10110;
          description = "UDP port ais-catcher sends NMEA0183 to.";
        };
      };
    };

    motor = {
      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "2341";
        description = "USB idVendor for the autopilot motor-controller symlink. null disables the rule.";
      };

      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "0042";
        description = "USB idProduct for the autopilot motor-controller symlink.";
      };

      symlink = mkOption {
        type = types.str;
        default = "pypilot_motor";
        description = "Name of the /dev symlink pointing at the motor controller.";
      };
    };
  };

  config = mkIf cfg.enable {

    # GPS served by gpsd, feeding signalk and the system clock.
    services.gpsd = mkIf cfg.gps.enable {
      enable = true;

      # Read immediately; a fix must come up without a client connected.
      nowait = true;

      # Autodetect: start with no device and let gpsdctl add hotplugged ones
      # over the control socket. Pinned: read the single configured device.
      devices = if gpsAutodetect then [ ] else [ cfg.gps.device ];
      extraArgs = optionals gpsAutodetect [
        "-F"
        "/run/gpsd.sock"
      ];
    };

    # gpsd reopens hotplugged devices after dropping privileges, so its user
    # needs serial access. Gate the whole user (mkIf on the leaf would still
    # materialise an empty, groupless gpsd user when gps is off).
    users.users.gpsd = mkIf cfg.gps.enable { extraGroups = [ "dialout" ]; };

    # Hotplug bridge: udev starts one instance per appearing GNSS device, which
    # tells the running gpsd to read it. Mirrors gpsd's shipped gpsdctl@ unit
    # but binds to this module's gpsd.service (not the unused gpsd.socket).
    systemd.services."gpsdctl@" = mkIf gpsAutodetect {
      description = "Hand %I to gpsd";
      after = [ "gpsd.service" ];
      requires = [ "gpsd.service" ];
      bindsTo = [ "dev-%i.device" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [ "GPSD_SOCKET=/run/gpsd.sock" ];
        ExecStart = "${pkgs.gpsd}/bin/gpsdctl add /dev/%I";
        ExecStop = "${pkgs.gpsd}/bin/gpsdctl remove /dev/%I";
      };
    };

    # Stable /dev names and hotplug triggers for GPS, AIS and the motor
    # controller, emitted only for the configured/known devices.
    services.udev.extraRules = concatStringsSep "\n" (

      # GPS: hotplug the GNSS list (autodetect) or pin one device by USB ID.
      (
        if gpsAutodetect then
          map gpsHotplugRule gpsHotplugIds
        else
          optional (cfg.gps.enable && hasGpsIds) (ttySymlink {
            inherit (cfg.gps) vendorId productId;
            name = gpsName;
          })
      )

      # AIS: stable symlink per known receiver so signalk's serial provider
      # finds it whenever it is plugged in.
      ++ optionals aisAutodetect (
        map (
          id:
          ttySymlink {
            inherit (id) vendorId productId;
            name = aisName;
          }
        ) aiscfg.autodetectIds
      )

      # RTL-SDR dongle readable by the ais-catcher service (system, not a seat
      # user, so uaccess does not apply — assign a group explicitly).
      ++ optionals aisSdr [
        ''SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", GROUP="plugdev", MODE="0660"''
        ''SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0660"''
      ]

      # Autopilot motor controller (pinned by USB ID).
      ++ optional hasMotorIds (ttySymlink {
        inherit (cfg.motor) vendorId productId;
        name = cfg.motor.symlink;
      })
    );

    # AIS via SDR: decode from the RTL-SDR dongle and forward NMEA over UDP to
    # the signalk SDR provider (:10110). The dongle conflicts with the kernel
    # DVB driver, so blacklist it. Dongle + reception are bench items (level 3).
    boot.blacklistedKernelModules = mkIf aisSdr [ "dvb_usb_rtl28xxu" ];
    users.groups.plugdev = mkIf aisSdr { };

    systemd.services.ais-catcher = mkIf aisSdr {
      description = "AIS-catcher SDR receiver feeding Signal K over UDP";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.ais-catcher}/bin/AIS-catcher -d:0 -u 127.0.0.1 ${toString aiscfg.sdr.udpPort}";
        DynamicUser = true;
        SupplementaryGroups = [ "plugdev" ];
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    assertions = [
      {
        assertion = (cfg.gps.vendorId == null) == (cfg.gps.productId == null);
        message = "services.navigation.gps: set both vendorId and productId, or neither.";
      }
      {
        assertion = (cfg.motor.vendorId == null) == (cfg.motor.productId == null);
        message = "services.navigation.motor: set both vendorId and productId, or neither.";
      }
    ];

    warnings = optional (cfg.pypilot.enable && cfg.hardware == null) (
      "services.navigation: pypilot is enabled without a HAT (hardware = null); "
      + "the IMU and control head will be unavailable."
    );
  };
}
