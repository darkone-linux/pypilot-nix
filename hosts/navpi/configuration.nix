# navpi — production host aboard. Raspberry Pi 4 by default.

{ ... }:

{
  imports = [ ../rpi.nix ];

  networking.hostName = "navpi";

  # HAT fitted on the Pi — pypilot-hat by default; uncomment to switch.
  services.navigation.hardware = "pypilot-hat";
  # services.navigation.hardware = "macarthur-hat";

  # Expose the Signal K hub to the boat network (chartplotters, tablets).
  services.navigation.signalk.openFirewall = true;

  # Stable /dev names from USB IDs (`lsusb`). Set to enable gps0 + gpsd time
  # sync and the autopilot motor symlink.
  # services.navigation.gps.vendorId = "1546";
  # services.navigation.gps.productId = "01a7";
  # services.navigation.motor.vendorId = "2341";
  # services.navigation.motor.productId = "0042";
}
