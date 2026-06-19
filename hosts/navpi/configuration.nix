# navpi — production host: Raspberry Pi 4 aboard, MacArthur HAT.

{ modulesPath, ... }:

{
  imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];

  networking.hostName = "navpi";

  # Expose the Signal K hub to the boat network (chartplotters, tablets).
  services.navigation.signalk.openFirewall = true;
}
