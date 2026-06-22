# integration.nix — level 2A integration test.
#
# Boots a VM running the navigation stack and checks the aarch64 (or x86_64)
# binaries run and the services come up and answer. Call with the target pkgs:
# aarch64-linux for the real target, x86_64-linux for fast local feedback.

{ pkgs }:

let
  # The nodes need the custom packages; apply the overlay here since
  # navigation.nix no longer sets nixpkgs.overlays itself.
  navPkgs = pkgs.extend (import ../pkgs);
in
navPkgs.testers.runNixOSTest {
  name = "navigation-integration";

  nodes.boat =
    { ... }:
    {
      imports = [ ../modules/navigation.nix ];

      services.navigation = {
        enable = true;
        signalk.enable = true;
        pypilot.enable = true;

        # No serial GPS in the VM; the daemon stack is exercised here and the
        # GPS path is simulated with gpsfake in the test script below.
        gps.enable = false;
      };

      # curl drives the Signal K API; gpsd ships gpsfake/gpspipe for the sim.
      environment.systemPackages = [
        pkgs.curl
        pkgs.gpsd
      ];

      virtualisation.memorySize = 2048;
    };

  testScript = ''
    boat.start()

    with subtest("Signal K data hub answers on :3000"):
        boat.wait_for_unit("signalk.service")
        boat.wait_for_open_port(3000)
        boat.succeed("curl -fsS http://localhost:3000/signalk >/dev/null")

    with subtest("pypilot autopilot daemon exposes its NMEA TCP port"):
        boat.wait_for_unit("pypilot.service")
        boat.wait_for_open_port(20220)

    with subtest("simulated GPS fix flows through gpsd"):
        boat.succeed(
            "gpsfake -n -c 0.1 ${./fixtures/sample.nmea} >/tmp/gpsfake.log 2>&1 &"
        )

        # Write to a file (no pipe → no SIGPIPE) then look for a position
        # report (TPV). gpsd emits TPV once it has a fix from the replay.
        boat.wait_until_succeeds(
            "gpspipe -w -n 20 > /tmp/gps.json 2>/dev/null; grep -q TPV /tmp/gps.json",
            timeout=90,
        )
  '';
}
