# pypilot-nix

[![CI](https://img.shields.io/github/actions/workflow/status/darkone-linux/pypilot-nix/ci.yml?branch=main&label=CI&logo=github)](https://github.com/darkone-linux/pypilot-nix/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-26.11+-blue.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![Platform](https://img.shields.io/badge/platform-aarch64--linux-lightgrey)](.)
[![Built with Nix](https://img.shields.io/badge/Built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)

**English** | [Français](README.fr.md)

**pypilot-nix** is a declarative NixOS distribution for embedded marine
navigation on Raspberry Pi: autopilot, data hub and chartplotter, reproducible
and version-controlled.

![PyPilot Nix Screenshot](doc/pypilot-nix-sc.png)

The whole stack comes up from a single NixOS option, builds into a bootable SD
image per boat, and updates over SSH like any other NixOS machine. Targets:
Raspberry Pi 4 (main) and Pi 5 (experimental) on `aarch64-linux`, with the
**Pypilot HAT** or the **MacArthur HAT**.

## Features

- **Single entry point**: `services.navigation.enable = true` wires the whole stack.
- **pypilot**: autopilot daemon with RTIMULib IMU fusion and motor control.
- **Signal K**: marine data hub on port 3000, NMEA0183 over TCP 10110.
- **OpenCPN**: chartplotter with generated config and a pypilot plugin slot.
- **Offline GPS clock**: `gpsd` and `chrony` set the time without Internet.
- **Hardware HATs**: I2C, UART and SPI buses, kernel modules and device-tree overlays.
- **Stable devices**: udev symlinks `/dev/gps0` and `/dev/pypilot_motor` from USB IDs.
- **Device discovery**: `nav-discover` lists serial gear and emits paste-ready Nix; a `serialDevices` registry wires udev + Signal K.
- **Encrypted secrets**: per-host wifi PSK via sops-nix, decrypted on-device; `just init <host>` mints the key and captures the password.
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

  # HATs fitted on the Pi, enable any combination:
  services.navigation.hardware.hats.enablePypilot = true;
  # services.navigation.hardware.hats.enableMacArthur = true;

  # Reach Signal K from the boat network:
  services.navigation.signalk.openFirewall = true;

  # Stable /dev names from `lsusb` IDs:
  # services.navigation.gps.vendorId = "1546";
  # services.navigation.gps.productId = "01a7";
}
```

Hosts shipped in the flake:

| Host        | Target                | HAT / module  | Role           |
| ----------- | --------------------- | ------------- | -------------- |
| `navpi`     | Raspberry Pi 4        | Pypilot HAT   | Production     |
| `lab-rpi4`  | Raspberry Pi 4        | Pypilot HAT   | Lab / bench    |
| `lab-rpi5`  | Raspberry Pi 5 ¹      | MacArthur HAT | Lab / bench    |
| `lab-rpi02` | Raspberry Pi Zero 2 W | Camera 3 Wide | Lab / camera ² |
| `lab-vm`    | aarch64 VM            | none          | Emulated lab   |

¹ Pi 5 boot support is experimental (generic aarch64 image).
² Headless Wi-Fi node: streams its CSI camera over RTSP/WebRTC.

Add a boat or bench by declaring one more `nixosConfigurations` entry in
`flake.nix` and dropping a `hosts/<host>/configuration.nix`; the modules are
shared, so no logic is duplicated. The full option set lives in
`modules/navigation.nix`.

## Network: gateway & hotspot

The `network` module turns the box into a LAN router and/or a WiFi access point
over a fixed `172.16.0.0/16` (the box is `172.16.0.1`), with dnsmasq serving DHCP
and DNS. Both roles are off until configured:

- **Gateway**: set `upstreamInterface` to the Internet uplink. Every *other*
  interface is bridged into the LAN and NATed out through it. One gateway per LAN.
- **Hotspot**: set `hotspot.enable = true` to broadcast a WPA2 AP (defaults: SSID
  `<Hostname>OnBoardWifi`, password `ILikePyPilot`, on `wlan0`). With a gateway it
  joins the same LAN and DHCP pool; standalone it serves its own.

Pin addresses with `fixedIps` (MAC → IP, inside `172.16.0.2`–`172.16.0.254`):

```nix
services.navigation.network = {
  upstreamInterface = "eth0";          # gateway role (omit for hotspot-only)
  hotspot.enable = true;               # WiFi access point
  fixedIps."de:ad:be:ef:00:11" = "172.16.0.10";
};
```

Change the AP SSID/password before going to sea — they are world-readable in the
Nix store.

## Supported hardware

HATs sit on the 40-pin header; add-on modules use their own connectors. Enable
any combination through `services.navigation.hardware` — each is a boolean, and
GPIO conflicts between two HATs are caught by assertions at build time. USB serial
gear (GPS, AIS, sensors) is **not** a HAT: discover and wire it with
[`nav-discover`](#serial-devices--discovery) (see below) before reaching for these
toggles.

| Hardware                | Type   | Enable option (`services.navigation.`…)   | Status       |
| ----------------------- | ------ | ----------------------------------------- | ------------ |
| Pypilot HAT             | HAT    | `hardware.hats.enablePypilot`             | ✅ supported |
| MacArthur HAT           | HAT    | `hardware.hats.enableMacArthur`           | 🚧 testing   |
| Camera Module 3 Wide    | module | `hardware.modules.enableCamera3Wide`      | 🚧 testing   |
| Kitronik 5038 AQ HAT    | HAT    | `hardware.hats.enableAqc5038`             | 🚧 testing   |
| SIM7600X 4G/LTE HAT     | HAT    | `hardware.hats.enableSim7600x`            | 🚧 testing   |
| XPT2046 touchscreen HAT | HAT    | `hardware.hats.enableXpt2046`             | 🚧 testing   |

> Only the Pypilot HAT is bench-validated. The others are implemented but still
> **in testing** — they get the ✅ once confirmed working on real hardware.

### Pypilot HAT

Autopilot brain: ICM20948 IMU (I2C), LCD + keypad (SPI0) and the motor controller
on UART0 (`/dev/ttyOP_pilot`).

```nix
services.navigation.hardware.hats.enablePypilot = true;
```

Use it through pypilot's web UI (`pypilot_web`, port 8000) for IMU calibration and
steering, or the pypilot plugin in OpenCPN when the desktop is on. A USB motor
controller is pinned with a `serialDevices` entry using `role = "pilot"`.

### MacArthur HAT

Multiplexed marine I/O: MCP2515 CAN for **NMEA2000** (SPI0), an on-board **AIS**
receiver on UART0 (`ttyAMA0`), a DS3231 RTC and an SC16IS752 dual UART (I2C).

```nix
services.navigation.hardware.hats.enableMacArthur = true;
```

NMEA2000 and AIS flow into Signal K automatically; the RTC keeps time offline.
Pinout follows the HAT conventions; still in testing on real hardware.

### Camera Module 3 Wide

IMX708 wide camera on the CSI connector — no header GPIO, so compatible with any
HAT above.

```nix
services.navigation.hardware.modules.enableCamera3Wide = true;

# Optional: stream over the network (RTSP + WebRTC) via MediaMTX
services.navigation.hardware.modules.camera3Wide.streaming = {
  enable = true;
  openFirewall = true; # opens 8554/tcp (RTSP), 8889/tcp + 8189/udp (WebRTC)
  # width = 1280; height = 720; framerate = 30;
};
```

`cam --list` on the host confirms the sensor. With streaming on, connect from any
machine: WebRTC in a browser at `http://<host>.local:8889/cam`, or RTSP at
`rtsp://<host>.local:8554/cam` (VLC, mpv). Hardware H.264 encoding keeps the CPU
idle, and the camera only powers up while a client is connected.

### Kitronik 5038 Air Quality Control HAT

Environmental sensing and I/O: a **BME688** (temperature, pressure, humidity, air
quality index, eCO2) and a 128x64 **OLED** on I2C, plus an on-board **RP2040**
co-processor on `serial0` driving 3 ZIP LEDs, three ADC inputs and an RTC. Header
GPIOs break out a buzzer, two 1A outputs and a servo.

```nix
services.navigation.hardware.hats.enableAqc5038 = true;
```

The module enables I2C, frees `serial0` for the RP2040 and installs `i2c-tools`
plus a python3 with `pyserial` + `smbus2` (the protocols the HAT speaks).
`i2cdetect -y 1` confirms the BME688 (0x76/0x77) and OLED (0x3c). Kitronik's
driver is not in nixpkgs; install it in a venv with
`pip install KitronikAirQualityControlHAT`. Details: [`doc/aqc5038.fr.md`](doc/aqc5038.fr.md).

### SIM7600X 4G/LTE HAT

Cellular uplink and **GNSS**: a SIMCOM modem on USB (QMI `wwan0` for data, plus
NMEA/AT serial ports). Managed by **ModemManager** alongside the host's wifi.

```nix
services.navigation.hardware.hats.enableSim7600x = true;
services.navigation.sim7600xHat = {
  apn = "internet"; # empty = auto-detect
  gps.enable = true;
};
```

`mmcli -m any` shows the modem; the data bearer comes up at boot and the GPS NMEA
port is exposed as `/dev/ttySIM_gps`. The QMI raw-ip/DHCP path still needs bench
confirmation. Details: [`doc/sim7600x.fr.md`](doc/sim7600x.fr.md).

### XPT2046 touchscreen HAT

SPI TFT (Waveshare-style 3.5" **ILI9486**) with an **XPT2046/ADS7846** resistive
touch controller, both on SPI0. Shares SPI0 with the Pypilot/MacArthur HATs, so
it cannot be combined with them.

```nix
services.navigation.hardware.hats.enableXpt2046 = true;
services.navigation.xpt2046Hat.rotate = 90; # 0/90/180/270
```

The display comes up as `/dev/fb1` and the touch as a `/dev/input` device;
calibrate with `ts_calibrate` or `xinput_calibrator`. Panel binding and touch axes
still need bench confirmation. Details: [`doc/xpt2046.fr.md`](doc/xpt2046.fr.md).

## Serial devices & discovery

Marine gear (AIS, GPS, depth/wind sensors, the autopilot motor controller)
connects via USB or HAT. pypilot-nix wires it declaratively through a single
registry, and ships a discovery CLI to fill it.

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

- **`match`** pins the device: by USB `vendorId` + `productId` (optionally
  `serial` to tell identical adapters apart), or by `port` (a device-tree path
  such as `fe201000.serial:0.0`) for a soldered UART with no USB ID.
- **`role`** drives the wiring:

  | role       | udev symlink | service | Signal K provider     |
  | ---------- | ------------ | ------- | --------------------- |
  | `ais`      | yes          | signalk | NMEA0183 serial @ baud |
  | `nmea0183` | yes          | signalk | NMEA0183 serial @ baud |
  | `pilot`    | yes          | pypilot | none (pypilot owns it) |

The **GPS** stays on its own option, `services.navigation.gps` (gpsd owns the
receiver and disciplines the clock). NMEA2000/CAN is handled by the MacArthur
HAT module, not this registry. The legacy `ais`/`motor` options still work: they
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

### Signal K settings

Signal K's `settings.json` lives in its state dir (`/var/lib/signalk`), owned by
the running server and its web UI. It is seeded from Nix on first start only —
**except `pipedProviders`** (the data sources: gpsd, pypilot, serial AIS, SDR
AIS), which Nix owns and reconciles on **every** start. So enabling a source
(e.g. `services.navigation.ais.sdr.enable`) takes effect on the next
`nixos-rebuild switch`, no manual reset; a connection edited in the web UI lasts
until the next restart, when the declarative config wins. Other keys (port,
security, installed plugins) keep their seeded/runtime value — delete
`settings.json` to re-seed them.

## Secrets & wifi (sops)

Per-host secrets — today the wifi PSK of a headless node like `lab-rpi02` — are
kept encrypted with [sops-nix](https://github.com/Mic92/sops-nix). The plaintext
never enters git nor the Nix store: `secrets/<host>.yaml` is committed
**encrypted** and decrypted on the device at activation into `/run/secrets`.

`just init <host>` provisions a host in one idempotent step:

```shell
nix develop          # brings just + sops + age + yq into PATH
just init lab-rpi02  # mint key, register it, capture the wifi password
```

It mints the host's age key in `secrets/keys/<host>.txt` (**never committed**),
registers its public key in `.sops.yaml`, and — if the host enables wifi —
prompts once for the password and writes the encrypted `secrets/<host>.yaml`.
Re-running keeps an existing key/secret. Commit `secrets/<host>.yaml` and
`.sops.yaml` afterwards; the (non-secret) SSID stays in
`hosts/<host>/configuration.nix`.

Before the first boot of a headless box, copy its **private** key onto the SD
boot partition where the host reads it (`sops.age.keyFile`):

```shell
cp secrets/keys/lab-rpi02.txt /run/media/$USER/FIRMWARE/secrets/age.txt
# path on the Pi: /boot/firmware/secrets/age.txt
```

Without that key the device cannot decrypt the PSK, never joins wifi, and — being
headless — stays unreachable; the build warns when the secret is missing.

> Anyone with the physical card can read that key and the on-card encrypted
> secret: with no TPM, physical possession means access. sops protects the repo,
> CI and binary cache — not a stolen card. Rotate the PSK if a card is lost.

Full workflow and rotation: [`secrets/README.md`](secrets/README.md).

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
target: the wrong device wipes a disk):

```shell
zstd -dc result-navpi/sd-image/*.img.zst \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### 2. First boot

The image ships with SSH and mDNS enabled, reachable at `<host>.local`:

- user `skipper`, password `NixPypilot` (bootstrap default, change it)
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
| `just init <host>`        | Mint a host's sops age key and capture its wifi PSK   |
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
