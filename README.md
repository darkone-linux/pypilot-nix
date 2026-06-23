# pypilot-nix

[![CI](https://img.shields.io/github/actions/workflow/status/darkone-linux/pypilot-nix/ci.yml?branch=main&label=CI&logo=github)](https://github.com/darkone-linux/pypilot-nix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-26.11+-blue.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![Platform](https://img.shields.io/badge/platform-aarch64--linux-lightgrey)](.)
[![Built with Nix](https://img.shields.io/badge/Built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)

**English** | [Français](README.fr.md)

**pypilot-nix** is a declarative NixOS distribution for embedded marine
navigation on Raspberry Pi — a reproducible, version-controlled equivalent of
OpenPlotter.

The whole autopilot / data-hub / chartplotter stack comes up from a single
NixOS option, builds into a bootable SD image per boat, and updates over SSH
like any other NixOS machine. It targets Raspberry Pi 4 (main) and Pi 5
(experimental) on `aarch64-linux`, with the **Pypilot HAT** or the
**MacArthur HAT**.

## Features

- **Single entry point**: `services.navigation.enable = true` wires the whole stack.
- **pypilot**: autopilot daemon with RTIMULib IMU fusion and motor control.
- **Signal K**: marine data hub on port 3000, NMEA0183 over TCP 10110.
- **OpenCPN**: chartplotter with generated config and a pypilot plugin slot.
- **Offline GPS clock**: `gpsd` and `chrony` set the time without Internet.
- **Hardware HATs**: I2C, UART and SPI buses, kernel modules and device-tree overlays.
- **Stable devices**: udev symlinks `/dev/gps0` and `/dev/pypilot_motor` from USB IDs.
- **Device discovery**: `nav-discover` lists serial gear and emits paste-ready Nix; a `serialDevices` registry wires udev + Signal K.
- **Per-host SD images**: a named `pypilot-nix-<host>.img.zst` for each machine.
- **Tested in CI**: package import checks plus a NixOS VM integration test.
- **Headless**: SSH, mDNS `.local`, a `skipper` admin account, no display needed.

## Configuration

`hosts/common.nix` brings the stack up (`services.navigation.enable`) with the
headless services on by default. A per-host file then only sets the hostname and
the HAT:

```nix
# hosts/navpi/configuration.nix
{ ... }:
{
  imports = [ ../rpi.nix ];

  networking.hostName = "navpi";

  # HAT fitted on the Pi — pick one:
  services.navigation.hardware = "pypilot-hat";
  # services.navigation.hardware = "macarthur-hat";

  # Reach Signal K from the boat network:
  services.navigation.signalk.openFirewall = true;

  # Stable /dev names from `lsusb` IDs:
  # services.navigation.gps.vendorId = "1546";
  # services.navigation.gps.productId = "01a7";
}
```

Hosts shipped in the flake:

| Host       | Target           | HAT           | Role         |
| ---------- | ---------------- | ------------- | ------------ |
| `navpi`    | Raspberry Pi 4   | Pypilot HAT   | Production   |
| `lab-rpi4` | Raspberry Pi 4   | Pypilot HAT   | Lab / bench  |
| `lab-rpi5` | Raspberry Pi 5 ¹ | MacArthur HAT | Lab / bench  |
| `lab-vm`   | aarch64 VM       | none          | Emulated lab |

¹ Pi 5 boot support is experimental (generic aarch64 image).

Add a boat or bench by declaring one more `nixosConfigurations` entry in
`flake.nix` and dropping a `hosts/<host>/configuration.nix`; the modules are
shared, so no logic is duplicated. The full option set lives in
`modules/navigation.nix`.

## Serial devices & discovery

Marine gear (AIS, GPS, depth/wind sensors, the autopilot motor controller) plugs
in as USB or soldered serial ports. pypilot-nix wires them declaratively through
a single registry, and ships a discovery CLI to fill it — the reproducible
equivalent of OpenPlotter's "Serial" app.

### The `serialDevices` registry

One option is the source of truth for both the udev symlink and the Signal K
provider. The attribute name is the `/dev` symlink:

```nix
services.navigation.serialDevices.ttyOP_ais = {
  match = { vendorId = "27c5"; productId = "0402"; serial = "793379380P51"; };
  role = "ais"; # ais | nmea0183 | pilot
  baudrate = 38400;
};
```

- **`match`** pins the device, like OpenPlotter's *remember*: by USB
  `vendorId` + `productId` (optionally `serial` to tell identical adapters
  apart), or by `port` (a device-tree path such as `fe201000.serial:0.0`) for a
  soldered UART with no USB ID.
- **`role`** drives the wiring:

  | role       | udev symlink | service | Signal K provider     |
  | ---------- | ------------ | ------- | --------------------- |
  | `ais`      | yes          | signalk | NMEA0183 serial @ baud |
  | `nmea0183` | yes          | signalk | NMEA0183 serial @ baud |
  | `pilot`    | yes          | pypilot | none (pypilot owns it) |

The **GPS** stays on its own option, `services.navigation.gps` (gpsd owns the
receiver and disciplines the clock). NMEA2000/CAN is handled by the MacArthur
HAT module, not this registry. The legacy `ais`/`motor` options still work — they
are translated into registry entries internally.

### Discover devices with `nav-discover`

`nav-discover` is a read-only CLI (installed on every host) that enumerates the
serial ports and prints a ready-to-paste Nix snippet for each:

```shell
nav-discover         # list devices, guess the role from the USB ID
nav-discover --sniff # open each port, read NMEA0183 and detect the role
```

Workflow: plug the hardware in, run `nav-discover [--sniff]`, paste the snippet
into `hosts/<host>/configuration.nix`, then `nixos-rebuild switch`. A detected
GPS yields a `services.navigation.gps` snippet; AIS and sensors yield
`serialDevices` entries.

`--sniff` will not open a port already held by gpsd or Signal K, so run the scan
before assigning the device (or stop the consuming service first). On a host with
the labwc desktop, the same scan is available from the right-click menu under
**Outils → Scan Matériel**.

## Build the SD image

SD images are `aarch64`, so build them on a native ARM machine, a remote
builder, or an x86_64 host with `binfmt` emulation. The `nix-community` cache
avoids recompiling the bulk of the system.

```shell
just sd-image navpi
# or: nix build .#packages.aarch64-linux.navpi-sdImage -o result-navpi
```

The result is a compressed image:

```
result-navpi/sd-image/pypilot-nix-navpi.img.zst
```

SD-image hosts: `navpi`, `lab-rpi4`, `lab-rpi5`. The `lab-vm` runs as a VM (see
below).

## Installation

### 1. Flash the SD card

The image is zstd-compressed; decompress and write in one pipe (double-check the
target — the wrong device wipes a disk):

```shell
zstd -dc result-navpi/sd-image/*.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### 2. First boot

The image ships with SSH and mDNS enabled, reachable at `<host>.local`:

- user `skipper`, password `NixPypilot` (bootstrap default — change it)
- for passwordless deploys, add your key to
  `users.users.skipper.openssh.authorizedKeys.keys` and rebuild

### 3. Iterate over SSH

No re-flashing afterwards: build locally and push the closure.

```shell
nixos-rebuild switch \
  --flake .#navpi \
  --target-host skipper@navpi.local --use-remote-sudo \
  --build-host localhost
```

For automatic rollback on failure, add the `deploy-rs` input and use
`deploy .#<host>` (not wired here yet).

### Lab VM (no hardware)

Run the persistent aarch64 lab VM (on an aarch64 host, or x86_64 with binfmt
full-system emulation), then update it like a real Pi:

```shell
nix run .#lab-vm
nixos-rebuild switch --flake .#lab-vm --target-host skipper@lab-vm.local --use-remote-sudo
```

## Just recipes

The `Justfile` bundles the day-to-day commands. Run `just` (or `just --list`)
to see them all.

| Recipe                    | What it does                                          |
| ------------------------- | ----------------------------------------------------- |
| `just clean`              | `fix` + `check` + `format` (run before committing)    |
| `just sd-image <host>`    | Build the SD image for a host                         |
| `just apply <host> [act]` | Deploy a host over SSH (`act` defaults to `switch`)   |
| `just update`             | Update flake inputs, commit `flake.lock` if it changed |
| `just gc <host>`          | Free space on a host, then regenerate its boot entries |

```shell
just apply lab-rpi4          # nixos-rebuild switch on lab-rpi4
just apply lab-rpi4 boot     # stage for next boot instead of switching now
just update                  # bump inputs, auto-commit the lockfile
just gc lab-rpi4             # nix-collect-garbage -d over SSH, refresh bootloader
```

Deploy recipes target `skipper@<host>` over SSH and use the host's own `sudo`,
so the `skipper` key must be authorized and the account a sudoer.

## Documentation

See [`doc/pypilot-nix-specs.md`](doc/pypilot-nix-specs.md) for the full design,
the data-flow plumbing and the test strategy.
