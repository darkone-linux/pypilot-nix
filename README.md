# pypilot-nix

Declarative NixOS distribution for embedded marine navigation on Raspberry Pi.

## Features

- **Single entry point** — enable `services.navigation` and get the whole
  marine stack wired: autopilot, data hub, chartplotter, GPS time sync.
- **pypilot** — autopilot server with IMU fusion and motor control
  (ICM20948, MPU9250).
- **Signal K server** — marine data hub on `:3000`, feeding NMEA over
  TCP `:10110`, auto-discovered by pypilot via zeroconf.
- **OpenCPN** — chartplotter pre-configured with the pypilot plugin for
  route following.
- **GPS time synchronisation** — `gpsd` + `chrony` clocks the system from GPS
  without Internet (PPS support optional).
- **Hardware HATs** — udev rules, I2C, UART and device-tree overlays for
  **Pypilot HAT** and **MacArthur HAT**.
- **Declarative udev** — stable `/dev/gps0`, `/dev/pypilot_motor` symlinks
  from USB vendor/product IDs.
- **Rollback-safe deploys** — `nixos-rebuild` over SSH or
  [`deploy-rs`](https://github.com/serokell/deploy-rs) with automatic
  rollback.
- **Headless-by-default** — SSH, Avahi (`.local`), admin account (`skipper`),
  ready to run on a Pi without a display.

## Installation

### Prerequisites

- Raspberry Pi 4 or 5.
- MicroSD card (or USB boot medium).
- A Nix-enabled host (for the initial build, or use the binary cache).

### Bootstrap (first time)

Generate and flash a bootable SD image for your hardware:

```shell
# Build the SD image (e.g. for banc-rpi4)
nix build .#nixosConfigurations.banc-rpi4.config.system.build.sdImage

# Flash to SD card
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Supported hosts: `banc-rpi4`, `banc-rpi5`, `navpi`, `lab-vm`.

### Iterative updates

Once the Pi is booted and reachable on the network:

```shell
nixos-rebuild switch \
  --flake .#<host> \
  --target-host root@<host>.local \
  --build-host localhost
```

For automatic rollback on failure, use `deploy-rs`:

```shell
deploy .#<host>
```

### Quick lab VM

An aarch64 VM for offline development:

```shell
nix run .#lab-vm
```

Then push updates just like a real Pi:

```shell
nixos-rebuild switch \
  --flake .#lab-vm \
  --target-host root@lab-vm.local \
  --build-host localhost
```

## Project status

Early development — see [specifications](doc/pypilot-nix-specs.md) for the
full implementation plan.
