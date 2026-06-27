# Pure helpers for the network module (gateway + hotspot).
#
# Kept out of the module system so they stay unit-testable in isolation
# (tests/unit/lib/network_test.nix). They operate on plain values: a host name,
# a MAC/IP string, or the `fixedIps` attrset (MAC -> IP).

{ lib }:
rec {

  # Uppercase the first character; used to derive the per-host SSID prefix.
  capitalizeFirst =
    s:
    if s == "" then "" else lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (lib.stringLength s) s;

  # Default access-point SSID, named after the host ("lab-rpi4" -> ...).
  defaultSsid = hostName: "${capitalizeFirst hostName}OnBoardWifi";

  # Canonical MAC: six colon-separated hex octets (case-insensitive).
  validMac = mac: builtins.match "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" mac != null;

  # A fixed IP must sit in the reserved sub-range 172.16.0.2-172.16.0.254: the
  # .1 is the gateway, .0/.255 are network/broadcast.
  validFixedIp =
    ip:
    let
      m = builtins.match "172\\.16\\.0\\.([0-9]+)" ip;
      last = if m == null then null else lib.toInt (builtins.head m);
    in
    m != null && last >= 2 && last <= 254;

  # Human-readable rule violations for a `fixedIps` attrset, in a stable order
  # (bad MAC, out-of-range IP, then duplicated IP); each becomes one assertion.
  fixedIpsErrors =
    fixedIps:
    let
      ips = lib.attrValues fixedIps;

      # Values assigned to more than one MAC, deduplicated for a single message.
      dupIps = lib.unique (lib.filter (ip: lib.count (x: x == ip) ips > 1) ips);

      macErrors = map (m: "network.fixedIps: invalid MAC address \"${m}\".") (
        lib.filter (m: !validMac m) (lib.attrNames fixedIps)
      );

      ipErrors = lib.mapAttrsToList (
        m: ip: "network.fixedIps: ${m} -> ${ip} is outside 172.16.0.2-172.16.0.254."
      ) (lib.filterAttrs (_: ip: !validFixedIp ip) fixedIps);

      dupErrors = map (ip: "network.fixedIps: ${ip} is assigned to more than one MAC.") dupIps;
    in
    macErrors ++ ipErrors ++ dupErrors;
}
