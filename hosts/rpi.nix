# rpi.nix — shared Raspberry Pi base for every Pi host.
#
# Pulls in the generic aarch64 SD image (u-boot + extlinux), which applies the
# device-tree overlays declared by the hardware modules, and names the image
# per host.

{ config, modulesPath, ... }:

{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  # Image file named pypilot-nix-<host>-<version>-<system>.img.zst.
  image.baseName = "pypilot-nix-${config.networking.hostName}";
}
