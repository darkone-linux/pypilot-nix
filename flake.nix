{
  description = "pypilot-nix — declarative NixOS marine navigation distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      # Dev/build hosts: aarch64 is the deploy target, x86_64 for emulated builds.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      navPackages = pkgs: import ./pkgs pkgs;
    in
    {
      packages = forAllSystems (
        pkgs:
        (navPackages pkgs)
        // {
          default = (navPackages pkgs).pypilot;
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
    };
}
