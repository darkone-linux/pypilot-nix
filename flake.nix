{
  description = "pypilot-nix — declarative NixOS marine navigation distribution";

  inputs = {
    # Vendor-firmware Raspberry Pi base: real config.txt + device-tree overlays
    # (DTBs ship __symbols__), so dtparam=spi/i2c and dtoverlay actually apply —
    # what the generic SD image could not do. It pins its own nixpkgs; we follow
    # it so the marine packages build against the very nixpkgs the Pi hosts use.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
    nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-raspberrypi,
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

      # Run `f` against nixpkgs extended with the marine overlay, per system.
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f (nixpkgs.legacyPackages.${system}.extend marineOverlay));

      # Only the marine packages (not all of nixpkgs) for the packages/checks
      # outputs: pick the overlay's own attribute names out of the extended set.
      marinePackages = pkgs: nixpkgs.lib.getAttrs (builtins.attrNames (marineOverlay pkgs pkgs)) pkgs;

      # A Raspberry Pi host on the vendor-firmware base. `board` is the list of
      # nixos-raspberrypi board modules (rpi-4/5 base + display); common.nix and
      # the sd-image builder are shared. Their nixosSystem brings the vendor
      # nixpkgs, kernel, firmware and bootloader.
      mkRpiHost =
        { board, modules }:
        nixos-raspberrypi.lib.nixosSystem {
          specialArgs = { inherit nixos-raspberrypi; };
          modules =
            board
            ++ [
              nixos-raspberrypi.nixosModules.sd-image
              ./hosts/common.nix
            ]
            ++ modules;
        };

      inherit (nixos-raspberrypi.nixosModules) raspberry-pi-4 raspberry-pi-5;

      # Plain aarch64 NixOS host (the lab VM boots no Pi firmware).
      mkVmHost =
        { modules }:
        nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
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
        (marinePackages pkgs)
        // {
          default = pkgs.pypilot;
        }
      )) { aarch64-linux = sdImages; };

      # Level 1 (package builds + their import/smoke checks) and level 2A (VM
      # integration test) — run by `nix flake check`.
      checks = forAllSystems (
        pkgs:
        (marinePackages pkgs)
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
      overlays.default = marineOverlay;

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
      # duplicating logic. Pi 4 helm/bench on the vendor base, Pi 5 bench, plus
      # a plain aarch64 VM for emulated integration.
      nixosConfigurations = {
        navpi = mkRpiHost {
          board = [
            raspberry-pi-4.base
            raspberry-pi-4.display-vc4
          ];
          modules = [ ./hosts/navpi/configuration.nix ];
        };

        lab-rpi4 = mkRpiHost {
          board = [
            raspberry-pi-4.base
            raspberry-pi-4.display-vc4
          ];
          modules = [ ./hosts/lab-rpi4/configuration.nix ];
        };

        lab-rpi5 = mkRpiHost {
          board = [
            raspberry-pi-5.base
            raspberry-pi-5.display-vc4
          ];
          modules = [ ./hosts/lab-rpi5/configuration.nix ];
        };

        lab-vm = mkVmHost {
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
