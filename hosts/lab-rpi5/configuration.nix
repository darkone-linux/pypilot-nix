# lab-rpi5 — Raspberry Pi 5 (experimental) lab host, MacArthur HAT.
#
# The generic aarch64 SD image targets the Pi 3/4 boot flow; Pi 5 has a
# different boot chain and is experimental here (no raspberry-pi-nix input).
# Booting must be validated on real hardware.

{ ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "lab-rpi5";
  services.navigation.hardware = "macarthur-hat";
}
