{
  description = "pypilot-nix — declarative NixOS marine navigation distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let

      # Dev/build hosts: aarch64 is the deploy target, x86_64 for emulated builds.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      navPackages = pkgs: (import ./pkgs) pkgs pkgs;

      # A NixOS host: shared base + per-host modules. Each host picks its HAT
      # via services.navigation.hardware in its own configuration.nix.
      mkHost =
        {
          system,
          modules,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./hosts/common.nix ] ++ modules;
        };

      # Per-host bootable SD images (aarch64), keyed `<host>-sdImage`. Only the
      # Raspberry Pi hosts produce one (the lab VM boots no SD card).
      rpiHosts = [
        "navpi"
        "lab-rpi4"
        "lab-rpi5"
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
        (navPackages pkgs)
        // {
          default = (navPackages pkgs).pypilot;
        }
      )) { aarch64-linux = sdImages; };

      # Level 1 (package builds + their import/smoke checks) and level 2A (VM
      # integration test) — run by `nix flake check`.
      checks = forAllSystems (
        pkgs:
        (navPackages pkgs)
        // {
          integration = import ./tests/integration.nix { inherit pkgs; };
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
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      # Adds the custom marine packages (pypilot, signalk-server, …) to pkgs;
      # the service modules resolve their default `package` through it.
      overlays.default = final: _prev: navPackages final;

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
        desktop = ./modules/desktop.nix;
      };

      # All hosts share the navigation modules; add boats/benches here without
      # duplicating logic.
      nixosConfigurations = {
        navpi = mkHost {
          system = "aarch64-linux";
          modules = [ ./hosts/navpi/configuration.nix ];
        };

        lab-rpi4 = mkHost {
          system = "aarch64-linux";
          modules = [ ./hosts/lab-rpi4/configuration.nix ];
        };

        lab-rpi5 = mkHost {
          system = "aarch64-linux";
          modules = [ ./hosts/lab-rpi5/configuration.nix ];
        };

        lab-vm = mkHost {
          system = "aarch64-linux";
          modules = [ ./hosts/lab-vm/configuration.nix ];
        };
      };

      # Run the persistent aarch64 lab VM (level 2B). Needs an aarch64-capable
      # host (native ARM or binfmt full-system emulation); update it afterwards
      # with `nixos-rebuild switch --flake .#lab-vm --target-host …`.
      apps.aarch64-linux.lab-vm = {
        type = "app";
        program = "${self.nixosConfigurations.lab-vm.config.system.build.vm}/bin/run-lab-vm-vm";
      };
    };
}
