# Tests for lib/hardware.nix — GPIO claim conflict detection.
# Run with: just test  (or: nix-unit --flake .#libTests)

{ navLib }:
let
  inherit (navLib.hardware) gpioConflicts gpioConflictMessage;

  # Real pin sets from the HAT modules.
  pypilot = {
    owner = "pypilot-hat";
    pins = [
      2
      3
      7
      8
      9
      10
      11
      14
      15
    ];
  };

  macarthur = {
    owner = "macarthur-hat";
    pins = [
      2
      3
      7
      8
      9
      10
      11
      14
      15
      24
      25
      26
    ];
  };

  # CSI camera: claims no header GPIO, compatible with every HAT.
  camera = {
    owner = "camera3-wide";
    pins = [ ];
  };

  # Both HATs drive the same buses (I2C-1, SPI0, UART0).
  sharedOwners = [
    "pypilot-hat"
    "macarthur-hat"
  ];
in
{

  # ----- gpioConflicts -----

  testNoClaimsNoConflict = {
    expr = gpioConflicts [ ];
    expected = { };
  };

  testSingleHatNoConflict = {
    expr = gpioConflicts [ pypilot ];
    expected = { };
  };

  testCameraCompatible = {
    expr = gpioConflicts [
      pypilot
      camera
    ];
    expected = { };
  };

  testPypilotMacarthurConflict = {
    expr = gpioConflicts [
      pypilot
      macarthur
    ];
    expected = {
      "2" = sharedOwners;
      "3" = sharedOwners;
      "7" = sharedOwners;
      "8" = sharedOwners;
      "9" = sharedOwners;
      "10" = sharedOwners;
      "11" = sharedOwners;
      "14" = sharedOwners;
      "15" = sharedOwners;
    };
  };

  # ----- gpioConflictMessage -----

  testMessageNullWhenOk = {
    expr = gpioConflictMessage [ pypilot ];
    expected = null;
  };

  testMessageNamesDevicesAndPins = {
    expr = gpioConflictMessage [
      pypilot
      macarthur
    ];
    expected =
      "services.navigation.hardware: pypilot-hat, macarthur-hat claim the same "
      + "BCM GPIO(s) 10, 11, 14, 15, 2, 3, 7, 8, 9; enable only one of these "
      + "HATs/modules.";
  };
}
