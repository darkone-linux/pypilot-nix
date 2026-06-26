# nav-discover — serial-device and HAT discovery CLI for the navigation stack.
#
# Read-only helper: enumerates tty devices (pyudev), probes i2c-1/USB to spot the
# fitted HATs (smbus2), optionally sniffs NMEA0183 to guess the role, and prints
# a ready-to-paste `services.navigation.*` block. It never edits configuration —
# the registry stays declarative.

{
  stdenvNoCC,
  python3,
}:

let
  # pyudev for enumeration, pyserial for --sniff, smbus2 for the HAT I2C probe.
  pyEnv = python3.withPackages (ps: [
    ps.pyudev
    ps.pyserial
    ps.smbus2
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "nav-discover";
  version = "0.1.0";

  src = ./nav-discover.py;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/nav-discover
    substituteInPlace $out/bin/nav-discover \
      --replace-fail '#!/usr/bin/env python3' '#!${pyEnv}/bin/python3'

    runHook postInstall
  '';

  meta = {
    description = "Discover serial navigation devices and HATs, emit Nix snippets";
    mainProgram = "nav-discover";
  };
}
