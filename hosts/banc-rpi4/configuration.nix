# banc-rpi4 — hardware test bench: Raspberry Pi 4, pypilot HAT.

{ modulesPath, ... }:

{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  networking.hostName = "banc-rpi4";
}
