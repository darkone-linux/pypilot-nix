# rpi.nix — shared Raspberry Pi base for every Pi host.
#
# The boot chain (vendor firmware, kernel, bootloader) and the SD-image builder
# come from nixos-raspberrypi (board + sd-image modules wired in the flake), so
# this file only carries Pi-wide tweaks. Device-tree needs (SPI/I2C/disable-bt)
# are expressed per-HAT through `hardware.raspberry-pi.config` (config.txt).

{ config, lib, ... }:

{
  # Name the produced image pypilot-nix-<host>-…; override the base module's
  # default "nixos-image-rpi4-uboot".
  image.baseName = lib.mkForce "pypilot-nix-${config.networking.hostName}";
}
