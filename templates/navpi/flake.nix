{
  description = "navpi — boat-specific navigation config (pypilot-nix downstream)";

  inputs = {
    # The shared distro. Default: online. For local co-development, drop a clone
    # (or symlink) of pypilot-nix at ./navpi-nix and the Justfile auto-injects
    # `--override-input pypilot-nix path:./navpi-nix` — like /etc/nixos pointing
    # at a local checkout. Nothing else to declare: nixos-raspberrypi, sops-nix
    # and the marine overlay all come through pypilot-nix's own lock.
    pypilot-nix.url = "github:darkone-linux/pypilot-nix";
  };

  # Prebuilt Pi kernel/firmware cache (mirrors pypilot-nix's nixConfig); without
  # it the vendor kernel recompiles under emulation.
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs =
    { self, pypilot-nix, ... }:
    {
      # One boat host, assembled by the distro's builder. Only the board enum and
      # the host file are ours; the whole boot/sd-image/services stack is
      # pypilot-nix. Add a host by repeating this block + the sdImage line below.
      nixosConfigurations.navpi = pypilot-nix.lib.mkHost {
        board = "rpi4";
        modules = [ ./hosts/navpi/configuration.nix ];
      };

      # Bootable SD image: `just sd-image navpi`.
      packages.aarch64-linux.navpi-sdImage = self.nixosConfigurations.navpi.config.system.build.sdImage;

      # Reuse the distro's dev shell (just, sops, age, yq, nix tooling) so the
      # Justfile recipes work here too: `nix develop`.
      devShells = pypilot-nix.devShells;
    };
}
