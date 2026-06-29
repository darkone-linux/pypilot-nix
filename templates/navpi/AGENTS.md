# AGENTS.md

Telegraph style. Local, gitignored (`/*.md`) — not committed.

## What this repo is

Downstream, boat-specific config. Consumes the **pypilot-nix** distro (modules,
packages, lib, host builder). Holds only: host files (`hosts/<host>/`), secrets,
the thin `flake.nix`. No module/package logic lives here.

## Link to the common project (pypilot-nix)

- Single flake input `pypilot-nix`. It carries its OWN lock: nixos-raspberrypi,
  sops-nix, the marine overlay. We DO NOT redeclare them.
- Hosts are built by `pypilot-nix.lib.mkHost { board; modules; sops?; display?; }`.
  - `board` enum: `rpi3 | rpi4 | rpi5 | rpi02 | vm`.
  - `mkHost` injects the shared `common.nix`, the board base, sd-image, and the
    image-name override. Our host file only sets `services.navigation.*`.
- Reproducibility chain: our `flake.lock` pins pypilot-nix; pypilot-nix's lock
  pins everything else.

## Local vs online distro (like /etc/nixos → local checkout)

- Default: `flake.nix` input points online (`github:darkone-linux/pypilot-nix`).
- Co-development: clone the distro at `./navpi-nix` (a real dir — a symlink
  resolves to an absolute path that nix rejects in pure eval). The Justfile
  detects it (`path_exists`) and injects `--override-input pypilot-nix
  path:./navpi-nix` into every nix command (`{{ override }}`). No flake edit.
- `./navpi-nix` is gitignored — never committed.
- Standalone (online) use needs the distro's `mkHost` to be PUSHED to github,
  then `just update` here to relock.

## Add a host

1. New `hosts/<host>/configuration.nix` (set `networking.hostName`, the HATs, USB
   IDs). No `imports` reaching into the distro — options come via `common.nix`.
2. In `flake.nix`: a `nixosConfigurations.<host> = pypilot-nix.lib.mkHost { … }`
   block + a `packages.aarch64-linux.<host>-sdImage` passthrough line.

## Secrets (sops)

- `just init <host>`: mints `secrets/keys/<host>.txt` (private age key, NEVER
  committed), registers its public key in `.sops.yaml`, and for wifi hosts
  encrypts the PSK into `secrets/<host>.yaml` (committed encrypted).
- Before first boot of a headless host: copy the private key onto the SD FAT
  partition at `/boot/firmware/secrets/age.txt`.

## just targets

- Here: `clean` (fix+check+format), `inspect`, `sd-image`, `init`, `apply`,
  `gc`, `update` — all override-aware.
- Distro-only (not here): `test` (lib unit tests), `bump` (distro release).
- `nix develop` reuses the distro's dev shell (just, sops, age, yq, nix tooling).

## Inherited conventions (from pypilot-nix)

- Nix: no `with lib;`; explicit `lib.x`. `mkIf`/`mkMerge` over imperative if/else.
- systemd units: every external binary by full store path `${pkgs.x}/bin/y`.
- Comments: English, concise, why-not-what; a blank line ALWAYS precedes a comment.
- After editing any Nix file: `just clean` then `just inspect` before commit.
