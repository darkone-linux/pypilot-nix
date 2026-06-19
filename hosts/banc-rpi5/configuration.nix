# banc-rpi5 — hardware test bench: Raspberry Pi 5 (experimental), MacArthur HAT.
#
# The generic aarch64 SD image targets the Pi 3/4 boot flow. Pi 5 has a
# different boot chain and is experimental here (no raspberry-pi-nix input);
# booting must be validated on the bench (level 3).

{ modulesPath, ... }:

{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  networking.hostName = "banc-rpi5";
}
