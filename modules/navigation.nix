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
#
# `navLib` (the project library) is injected via specialArgs by the flake host
# builders; a standalone consumer must provide it the same way.

{
  config,
  lib,
  pkgs,
  navLib,
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

  # How udev pins a registry device to its /dev name: USB identity or port path
  # (OpenPlotter's remember = dev | port).
  serialMatch = types.submodule {
    options = {
      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "27c5";
        description = "USB idVendor (hex, lowercase).";
      };
      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "0402";
        description = "USB idProduct (hex, lowercase).";
      };
      serial = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "793379380P51";
        description = "USB serial string, to disambiguate identical adapters (optional).";
      };
      port = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "fe201000.serial:0.0";
        description = "Device-tree/USB port path for soldered UARTs without USB ids (udev KERNELS match).";
      };
    };
  };

  # A generic serial device assigned to a stable /dev name and a role.
  serialDevice = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to wire this device.";
      };

      match = mkOption {
        type = serialMatch;
        description = "How udev pins the device to /dev/<name>: USB id (+serial) or port.";
      };

      role = mkOption {
        type = types.enum [
          "ais"
          "nmea0183"
          "pilot"
        ];
        description = ''
          Device role, driving the wiring:
          - ais / nmea0183: NMEA0183 serial source piped into Signal K;
          - pilot: autopilot motor controller (symlink only; pypilot owns it).
          GPS is handled by `services.navigation.gps` (gpsd owns the receiver).
        '';
      };

      baudrate = mkOption {
        type = types.ints.positive;
        default = 38400;
        description = "Serial baud rate (NMEA0183 AIS is 38400; many sensors are 4800).";
      };

      signalkId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Signal K provider id; defaults to the attribute name.";
      };
    };
  };

  gpsName = lib.removePrefix "/dev/" cfg.gps.device;
  aisName = lib.removePrefix "/dev/" aiscfg.device;

  hasGpsIds = cfg.gps.vendorId != null && cfg.gps.productId != null;
  hasMotorIds = cfg.motor.vendorId != null && cfg.motor.productId != null;

  gpsAutodetect = cfg.gps.enable && cfg.gps.autodetect;
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

  # udev: pin one resolved registry device to /dev/<name> (USB id or port).
  deviceRule =
    e:
    let
      usbMatch =
        ''ATTRS{idVendor}=="${e.vendorId}", ATTRS{idProduct}=="${e.productId}"''
        + lib.optionalString (e.serial != null) '', ATTRS{serial}=="${e.serial}"'';
      selector = if e.port != null then ''KERNELS=="${e.port}"'' else usbMatch;
    in
    ''SUBSYSTEM=="tty", ${selector}, SYMLINK+="${e.name}", GROUP="dialout", MODE="0660", TAG+="systemd"'';

  # Legacy ais option as registry entries: one udev match per known id, all
  # pointing at the same symlink; deduped to a single Signal K provider.
  legacyAis =
    if !aiscfg.enable then
      [ ]
    else if aiscfg.autodetect then
      map (id: {
        name = aisName;
        inherit (id) vendorId productId;
        serial = null;
        port = null;
        role = "ais";
        baudrate = aiscfg.baudrate;
        signalkId = "ais";
      }) aiscfg.autodetectIds
    else
      [
        {
          name = aisName;
          vendorId = null;
          productId = null;
          serial = null;
          port = null;
          role = "ais";
          baudrate = aiscfg.baudrate;
          signalkId = "ais";
        }
      ];

  # Legacy motor option as a registry entry (symlink only; pypilot owns it).
  legacyMotor = optional hasMotorIds {
    name = cfg.motor.symlink;
    inherit (cfg.motor) vendorId productId;
    serial = null;
    port = null;
    role = "pilot";
    baudrate = null;
    signalkId = null;
  };

  # User-declared devices, normalised to the same shape.
  userDevices = lib.mapAttrsToList (name: d: {
    inherit name;
    inherit (d.match)
      vendorId
      productId
      serial
      port
      ;
    inherit (d) role baudrate;
    signalkId = if d.signalkId != null then d.signalkId else name;
  }) (lib.filterAttrs (_: d: d.enable) cfg.serialDevices);

  # Single source of truth for udev symlinks and Signal K serial providers.
  resolvedDevices = userDevices ++ legacyAis ++ legacyMotor;

  # udev rules only for devices carrying a stable identifier (id or port).
  serialRules = map deviceRule (
    lib.filter (e: (e.vendorId != null && e.productId != null) || e.port != null) resolvedDevices
  );
in
{
  imports = [
    ./hardware
    ./pypilot.nix
    ./signalk.nix
    ./opencpn.nix
    ./gps-time.nix
    ./desktop
    ./development.nix
    ./cellular.nix
    ./network.nix
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

    serialDevices = mkOption {
      type = types.attrsOf serialDevice;
      default = { };
      example = lib.literalExpression ''
        {
          ttyOP_ais = {
            match = { vendorId = "27c5"; productId = "0402"; };
            role = "ais";
          };
        }
      '';
      description = ''
        Generic serial-device registry; the attribute name is the /dev symlink.
        Each entry generates a udev rule and, for ais/nmea0183 roles, a Signal K
        NMEA0183 serial provider. Fill it with the `nav-discover` CLI.
      '';
    };

    _resolved = mkOption {
      internal = true;
      visible = false;
      type = types.listOf types.attrs;
      default = [ ];
      description = "Internal: normalised serial devices, consumed by signalk.nix.";
    };
  };

  config = mkIf cfg.enable {

    services.navigation._resolved = resolvedDevices;

    # When both run, ship and enable OpenCPN's pypilot plugin automatically (no
    # need to wire `opencpn.plugins`/`enabledPlugins` by hand). The plugin
    # defaults to a hardcoded remote host (192.168.14.1); pin it to the
    # co-located pypilot so it connects over loopback out of the box.
    services.navigation.opencpn = mkIf (cfg.opencpn.enable && cfg.pypilot.enable) {
      plugins = [ pkgs.opencpn-plugin-pypilot ];
      enabledPlugins = [ "libpypilot_pi.so" ];
      extraConfig = ''
        [PlugIns/pypilot]
        Host=127.0.0.1
        AutoDiscover=0
      '';
    };

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

      # Registry devices (AIS, generic NMEA0183 sensors, motor controller):
      # one stable symlink per match, from the unified serial registry.
      ++ serialRules

      # RTL-SDR dongle readable by the ais-catcher service (system, not a seat
      # user, so uaccess does not apply — assign a group explicitly).
      ++ optionals aisSdr [
        ''SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", GROUP="plugdev", MODE="0660"''
        ''SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0660"''
      ]
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
        assertion = navLib.serial.pairComplete cfg.gps.vendorId cfg.gps.productId;
        message = "services.navigation.gps: set both vendorId and productId, or neither.";
      }
      {
        assertion = navLib.serial.pairComplete cfg.motor.vendorId cfg.motor.productId;
        message = "services.navigation.motor: set both vendorId and productId, or neither.";
      }
    ]
    ++ lib.mapAttrsToList (n: d: {

      # Exactly one match mode, with USB ids complete when used.
      assertion = navLib.serial.serialMatchValid d.match;
      message = "services.navigation.serialDevices.${n}.match: set exactly one of vendorId+productId (optionally serial) or port.";
    }) cfg.serialDevices;

    warnings =
      let
        hats = cfg.hardware.hats;
        anyHat = hats.enablePypilot || hats.enableMacArthur || hats.enableSim7600x || hats.enableXpt2046;
      in
      optional (cfg.pypilot.enable && !anyHat) (
        "services.navigation: pypilot is enabled without a HAT; "
        + "the IMU and control head will be unavailable."
      );
  };
}
