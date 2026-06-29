# mk-host.nix — host builder exposed as `lib.mkHost` for downstream flakes.
#
# Closes over the distro's own inputs (nixos-raspberrypi, sops-nix, navLib) so a
# consumer flake declares ONLY `pypilot-nix` as input: no vendor firmware nor
# secrets plumbing to redeclare. A `board` enum picks the Raspberry Pi base, the
# shared common.nix and sd-image are wired in here, and the boot/image specifics
# (formerly hosts/rpi.nix) are injected for every Pi board.

{
  nixpkgs,
  nixos-raspberrypi,
  sops-nix,
  navLib,
}:
let
  inherit (nixpkgs) lib;

  rpi = nixos-raspberrypi.nixosModules;

  # board enum → vendor base module, optional display-vc4 module, and whether the
  # helm display is on by default. rpi3 ships no display-vc4 in nixos-raspberrypi.
  boards = {
    rpi3 = {
      base = rpi.raspberry-pi-3.base;
      display = null;
      displayDefault = false;
    };
    rpi4 = {
      base = rpi.raspberry-pi-4.base;
      display = rpi.raspberry-pi-4.display-vc4;
      displayDefault = true;
    };
    rpi5 = {
      base = rpi.raspberry-pi-5.base;
      display = rpi.raspberry-pi-5.display-vc4;
      displayDefault = true;
    };
    rpi02 = {
      base = rpi.raspberry-pi-02.base;
      display = rpi.raspberry-pi-02.display-vc4;
      displayDefault = false;
    };
  };

  # Folded-in hosts/rpi.nix: name the produced image pypilot-nix-<host>-…,
  # overriding the base module's generic default. Pi boards only (the VM has no
  # sd-image).
  rpiImageName =
    { config, lib, ... }:
    {
      image.baseName = lib.mkForce "pypilot-nix-${config.networking.hostName}";
    };
in

# board : "rpi3" | "rpi4" | "rpi5" | "rpi02" | "vm"
# display : null → board default; true/false forces it (ignored where the board
#           has no display-vc4, e.g. rpi3).
# sops : pull in sops-nix.nixosModules.sops for hosts with encrypted secrets.
{
  board,
  display ? null,
  sops ? false,
  modules ? [ ],
}:
if board == "vm" then

  # Plain aarch64 NixOS host (the lab VM boots no Pi firmware).
  nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit navLib; };
    modules = [ ../hosts/common.nix ] ++ modules;
  }

else
  let
    b = boards.${board} or (throw "mkHost: unknown board '${board}' (rpi3|rpi4|rpi5|rpi02|vm)");
    displayOn = if display == null then b.displayDefault else display;
  in

  # Vendor-firmware Pi host: their nixosSystem brings the vendor nixpkgs, kernel,
  # firmware and bootloader.
  nixos-raspberrypi.lib.nixosSystem {
    specialArgs = { inherit nixos-raspberrypi navLib; };
    modules = [
      b.base
    ]
    ++ lib.optional (displayOn && b.display != null) b.display
    ++ [
      nixos-raspberrypi.nixosModules.sd-image
      ../hosts/common.nix
      rpiImageName
    ]
    ++ lib.optional sops sops-nix.nixosModules.sops
    ++ modules;
  }
