# navpi — production host aboard. Raspberry Pi 4. Downstream boat config: it
# consumes services.navigation.* (options come from pypilot-nix via mkHost →
# common.nix); no module/package paths reach back into the distro.

{ pkgs, ... }:

{
  networking.hostName = "navpi";

  # HATs fitted on the Pi — Pypilot by default; toggle others as needed.
  services.navigation.hardware.hats.enablePypilot = true;
  # services.navigation.hardware.hats.enableMacArthur = true;

  # Expose the Signal K hub to the boat network (chartplotters, tablets).
  services.navigation.signalk.openFirewall = true;

  # Chartplotter desktop on the helm screen (labwc, always-on).
  services.navigation.opencpn.enable = true;
  services.navigation.opencpn.plugins = [ pkgs.opencpn-plugin-pypilot ];
  services.navigation.opencpn.enabledPlugins = [ "libpypilot_pi.so" ];
  services.navigation.desktop.enable = true;

  # Pin USB gear by its `lsusb` ID (idVendor:idProduct, hex lowercase). Why per
  # host: generic serial chips (PL2303, CP210x, FTDI) share IDs across devices,
  # so the global autodetect lists stay conservative — pin yours here.
  #
  # - GPS: set gps.vendorId/productId → udev makes /dev/gps0, gpsd adopts it
  #   (plug-and-play + clock sync), and pypilot's serialprobe skips the port.
  # - AIS: add the receiver's ID to ais.autodetectIds → symlinked to the device
  #   signalk reads (this *replaces* the bench default; list every receiver).
  # - Motor: set motor.vendorId/productId → /dev/pypilot_motor for the autopilot.
  #
  # Default GPS below is the bench Prolific PL2303; swap for the boat's receiver.
  services.navigation.gps.vendorId = "067b";
  services.navigation.gps.productId = "2303";

  # services.navigation.ais.autodetectIds = [
  #   { vendorId = "1234"; productId = "5678"; }
  # ];
  # services.navigation.motor.vendorId = "2341";
  # services.navigation.motor.productId = "0042";
}
