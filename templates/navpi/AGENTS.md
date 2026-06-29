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

## Single source switch (like /etc/nixos → local checkout)

- `flake.lock` is the ONLY switch: the distro is whatever it pins. `just update`
  sets it — a local clone at `./navpi-nix` if present, else the online ref.
- Every other recipe (`inspect`, `sd-image`, `apply`) just reads the lock — no
  runtime override, never local+online mixed, never silent. `just pin` /
  `just status` print the current source.
- The local pin is stored as an ABSOLUTE path (nix canonicalises it). Fine for a
  solo workstation (builds happen here, the closure is pushed to the Pi). Before
  sharing/building elsewhere, `just update` with `./navpi-nix` removed re-pins
  online → portable, committable lock.
- `./navpi-nix` must be a real git clone (for `commit`/`amend`), and is gitignored:
  `git clone git@github.com:darkone-linux/pypilot-nix.git navpi-nix`.

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

- Dev/deploy: `clean` (fix+check+format), `inspect`, `sd-image`, `init`, `apply`,
  `gc` — all read the lock.
- Source & co-dev: `update` (re-pin local/online), `status` (pin + git of both
  repos), `commit "msg"` / `amend` (act on navpi-nix AND navpi at once, then
  re-pin). `commit`/`amend` run git in the distro clone too, so it must be a real
  clone.
- Distro-only (not here): `test` (lib unit tests), `bump` (distro release).
- `nix develop` reuses the distro's dev shell (just, sops, age, yq, nix tooling).

## Inherited conventions (from pypilot-nix)

- Nix: no `with lib;`; explicit `lib.x`. `mkIf`/`mkMerge` over imperative if/else.
- systemd units: every external binary by full store path `${pkgs.x}/bin/y`.
- Comments: English, concise, why-not-what; a blank line ALWAYS precedes a comment.
- After editing any Nix file: `just clean` then `just inspect` before commit.
