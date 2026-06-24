# Changelog

All notable changes to this project are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/darkone-linux/pypilot-nix/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/darkone-linux/pypilot-nix/releases/tag/v0.1.0
