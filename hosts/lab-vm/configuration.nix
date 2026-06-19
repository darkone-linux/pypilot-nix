# lab-vm — persistent aarch64 emulation lab (test level 2, mode B). No HAT.
#
# A plain headless host: build/run it as a VM (`nixos-rebuild build-vm` or the
# system.build.vm output) and then update it over SSH like any remote machine,
# unifying the workflow with the hardware bench. The navigation stack runs
# without sensors (hardware = null), which is exactly what level 2 validates.

{ modulesPath, ... }:

{
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

  networking.hostName = "lab-vm";

  # extlinux needs no ESP and satisfies the bootloader assertion; the build-vm
  # path overrides booting anyway.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
