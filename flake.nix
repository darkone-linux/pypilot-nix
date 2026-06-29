{
  description = "pypilot-nix — declarative NixOS marine navigation distribution";

  # Prebuilt Pi kernel/firmware: offered to the build machine (deploys build on
  # the x86_64 workstation, not the Pi), else the vendor kernel recompiles under
  # emulation. Trusted users get it automatically; others need
  # --accept-flake-config. Mirrors nixos-raspberrypi's own nixConfig.
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    # Track nixpkgs-unstable for the marine packages, dev shells and lab VM.
    # Decoupled from nixos-raspberrypi's pin: the Pi hosts still build their
    # kernel/firmware against the vendor nixpkgs (brought by its nixosSystem).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Vendor-firmware Raspberry Pi base: real config.txt + device-tree overlays
    # (DTBs ship __symbols__), so dtparam=spi/i2c and dtoverlay actually apply —
    # what the generic SD image could not do.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

    # Encrypted secrets (e.g. the lab-rpi02 wifi PSK): committed encrypted,
    # decrypted at activation on the device. Follows our nixpkgs.
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-raspberrypi,
      sops-nix,
      ...
    }:
    let

      # Dev/build hosts: aarch64 is the deploy target, x86_64 for emulated builds.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # The marine packages as a nixpkgs overlay (pkgs/default.nix); also exported
      # as overlays.default and applied by hosts/common.nix.
      marineOverlay = import ./pkgs;

      # Local navigation library (navLib), injected into modules via specialArgs
      # instead of per-module `import ../lib` (single source, no relative paths).
      navLib = import ./lib { inherit (nixpkgs) lib; };

      # Host builder exposed as `lib.mkHost`: a board enum (rpi3/rpi4/rpi5/rpi02/
      # vm) drives the whole boot/sd-image wiring, so downstream flakes declare
      # only `pypilot-nix` as input. Carries the distro's own input closure.
      mkHost = import ./lib/mk-host.nix {
        inherit
          nixpkgs
          nixos-raspberrypi
          sops-nix
          navLib
          ;
      };

      # Run `f` against nixpkgs extended with the marine overlay, per system.
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f (nixpkgs.legacyPackages.${system}.extend marineOverlay));

      # Only the marine packages (not all of nixpkgs) for the packages/checks
      # outputs: pick the overlay's own attribute names out of the extended set.
      marinePackages = pkgs: nixpkgs.lib.getAttrs (builtins.attrNames (marineOverlay pkgs pkgs)) pkgs;

      # Per-host bootable SD images (aarch64), keyed `<host>-sdImage`. Only the
      # Raspberry Pi hosts produce one (the lab VM boots no SD card).
      rpiHosts = [
        "lab-rpi4"
        "lab-rpi5"
        "lab-rpi02"
      ];
      sdImages = builtins.listToAttrs (
        map (name: {
          name = "${name}-sdImage";
          value = self.nixosConfigurations.${name}.config.system.build.sdImage;
        }) rpiHosts
      );
    in
    {
      packages = nixpkgs.lib.recursiveUpdate (forAllSystems (
        pkgs:
        (marinePackages pkgs)
        // {
          default = pkgs.pypilot;
        }
      )) { aarch64-linux = sdImages; };

      # Pure unit tests (nix-unit) over lib/. Run with `just test` or
      # `nix-unit --flake .#libTests`.
      libTests = import ./tests/unit { inherit (nixpkgs) lib; };

      # Level 1 (package builds + their import/smoke checks), the pure unit
      # suites (level 0) and level 2A (VM integration test) — run by
      # `nix flake check`.
      checks = forAllSystems (
        pkgs:
        (marinePackages pkgs)
        // {
          unit = import ./tests/unit-check.nix { inherit pkgs; };
          integration = import ./tests/integration.nix { inherit pkgs navLib; };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {

          # Tooling backing the Justfile recipes plus Nix/shell helpers.
          packages = [
            pkgs.just
            pkgs.statix
            pkgs.deadnix
            pkgs.treefmt
            pkgs.nixfmt
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.nil
            pkgs.nix-unit

            # Edit/encrypt secrets/*.yaml, mint the device age key, and let
            # `just init` patch .sops.yaml recipients.
            pkgs.sops
            pkgs.age
            pkgs.yq-go
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      # Adds the custom marine packages (pypilot, signalk-server, …) to pkgs;
      # the service modules resolve their default `package` through it.
      overlays.default = marineOverlay;

      # Pure navigation helpers (also injected into modules via specialArgs) plus
      # `mkHost`, the host builder downstream flakes call to assemble a config.
      lib = navLib // {
        inherit mkHost;
      };

      nixosModules = {

        # Orchestrator: single entry point importing every module below and
        # wiring the whole stack from `services.navigation.enable`.
        navigation = ./modules/navigation.nix;
        default = ./modules/navigation.nix;

        # Hardware HAT modules (selector + pypilot-hat + macarthur-hat).
        hardware = ./modules/hardware;

        # Service modules (own their services.navigation.<svc> options).
        pypilot = ./modules/pypilot.nix;
        signalk = ./modules/signalk.nix;
        opencpn = ./modules/opencpn.nix;
        desktop = ./modules/desktop;
        development = ./modules/development.nix;
        cellular = ./modules/cellular.nix;
        network = ./modules/network.nix;
      };

      # Example/bench hosts, all built through the same `mkHost` exposed to
      # downstream flakes (the real boat host lives in its own repo). Pi 4/5
      # benches, a wifi Pi Zero 2 W sensor node, plus a plain aarch64 VM for
      # emulated integration.
      nixosConfigurations = {
        lab-rpi4 = mkHost {
          board = "rpi4";
          modules = [ ./hosts/lab-rpi4/configuration.nix ];
        };

        lab-rpi5 = mkHost {
          board = "rpi5";
          modules = [ ./hosts/lab-rpi5/configuration.nix ];
        };

        # Pi Zero 2 W headless node: wifi-connected, Camera Module 3 Wide. No
        # helm display (camera/sensor box); sops decrypts its wifi PSK.
        lab-rpi02 = mkHost {
          board = "rpi02";
          sops = true;
          modules = [ ./hosts/lab-rpi02/configuration.nix ];
        };

        lab-vm = mkHost {
          board = "vm";
          modules = [ ./hosts/lab-vm/configuration.nix ];
        };
      };

      # Run the persistent aarch64 lab VM (level 2B). Needs an aarch64-capable
      # host (native ARM or binfmt full-system emulation); update it afterwards
      # with `nixos-rebuild switch --flake .#lab-vm --target-host …`.
      apps.aarch64-linux.lab-vm = {
        type = "app";
        program = "${self.nixosConfigurations.lab-vm.config.system.build.vm}/bin/run-lab-vm-vm";
        meta.description = "Run the persistent aarch64 lab VM (level 2B)";
      };

      # Scaffold a downstream boat project (own flake importing this distro, a
      # host file, portable Justfile, sops/.gitignore):
      # `nix flake init -t github:darkone-linux/pypilot-nix#navpi`.
      templates.navpi = {
        path = ./templates/navpi;
        description = "Downstream boat config consuming pypilot-nix via lib.mkHost";
      };
      templates.default = self.templates.navpi;
    };
}
