# Changelog

All notable changes to this project are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- New HAT modules: XPT2046 (SPI ILI9486 LCD with ADS7846 touchscreen),
  SIM7600X (4G/LTE via ModemManager plus GNSS), and Kitronik 5038 Air
  Quality Control.
- Camera Module 3 Wide support: streams the CSI camera over RTSP/WebRTC
  via MediaMTX.
- `nav-discover` now detects HATs over i2c/USB and emits the matching
  hardware toggles automatically.
- New host `lab-rpi02`: a Pi Zero 2 W wifi node with Camera Module 3 Wide.
- `just init <host>`: idempotent per-host sops age key and encrypted wifi
  PSK setup, with the PSK decrypted at activation through sops-nix.

## [0.1.1] - 2026-06-26

### Added

- Multi-HAT selection (`hardware.hats.*`) with GPIO conflict assertions that
  refuse incompatible HAT combinations at evaluation time.
- nix-unit test suites for the pure `lib/` algorithms (serial registry and
  GPIO-conflict detection), runnable via `just test` and `nix flake check`.
- labwc screenshot keybinds: Print captures the screen, Shift+Print a region
  (grim/slurp into `~/Captures`).

### Changed

- OpenCPN's pypilot plugin is shipped and enabled automatically when both
  `opencpn` and `pypilot` are on; no need to set `opencpn.plugins` by hand.
- labwc menus, panel quick-launch and keyboard shortcuts now follow the
  enabled services: OpenCPN, SignalK and the PyPilot submenu drop out when
  their service is off.
- Deploys pull from the nixos-raspberrypi Cachix cache to avoid rebuilding the
  kernel.
- `navLib` is injected via `specialArgs` instead of importing `../lib`.
- Bumped canboat to 6.2.2 and ais-catcher to 0.70.

### Fixed

- `flake.lock` is tracked to pin inputs, avoiding spurious kernel rebuilds.

## [0.1.0] - 2026-06-24

First public release. Declarative NixOS marine navigation distribution for
Raspberry Pi 4/5 (`aarch64-linux`), a reproducible OpenPlotter equivalent.

### Added

- `services.navigation` orchestrator wiring the whole stack.
- Packaged from source: pypilot (+ rtimulib2), signalk-server,
  opencpn-plugin-pypilot, canboat.
- Modules: pypilot, signalk, opencpn, gps-time, development toolbox,
  cellular modem, WiFi hotspot.
- Hardware modules: Pypilot HAT and MacArthur HAT overlays (i2c-dev,
  ttyAMA0, GPIO).
- Hosts: navpi (prod), lab-rpi4, lab-rpi5, lab-vm.
- labwc helm desktop: OpenCPN fullscreen, XyGrib, pypilot UI, panel
  telemetry (CPU, RAM, temperature), hardware scan menu.
- Plug-and-play USB GPS via gpsd, exposed as a SignalK source.
- `nav-discover` unified serial registry and CLI for GPS/AIS pinning.
- SD image builds per host; level-1 package and level-2A VM CI.

[Unreleased]: https://github.com/darkone-linux/pypilot-nix/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/darkone-linux/pypilot-nix/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/darkone-linux/pypilot-nix/releases/tag/v0.1.0
