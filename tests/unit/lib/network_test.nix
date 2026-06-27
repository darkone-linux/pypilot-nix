# Tests for lib/network.nix — gateway/hotspot helpers.
# Run with: just test  (or: nix-unit --flake .#libTests)

{ navLib }:
let
  inherit (navLib.network)
    capitalizeFirst
    defaultSsid
    validMac
    validFixedIp
    fixedIpsErrors
    ;
in
{

  # ----- capitalizeFirst -----

  testCapEmpty = {
    expr = capitalizeFirst "";
    expected = "";
  };

  testCapSingle = {
    expr = capitalizeFirst "x";
    expected = "X";
  };

  testCapHyphenHost = {
    expr = capitalizeFirst "lab-rpi4";
    expected = "Lab-rpi4";
  };

  testCapAlreadyUpper = {
    expr = capitalizeFirst "Navpi";
    expected = "Navpi";
  };

  # ----- defaultSsid -----

  testSsidFromHost = {
    expr = defaultSsid "lab-rpi4";
    expected = "Lab-rpi4OnBoardWifi";
  };

  # ----- validMac -----

  testMacValid = {
    expr = validMac "DE:AD:BE:EF:00:11";
    expected = true;
  };

  testMacLowercase = {
    expr = validMac "de:ad:be:ef:00:11";
    expected = true;
  };

  testMacTooShort = {
    expr = validMac "DE:AD:BE:EF:00";
    expected = false;
  };

  testMacNonHex = {
    expr = validMac "ZZ:AD:BE:EF:00:11";
    expected = false;
  };

  testMacWrongSeparator = {
    expr = validMac "DE-AD-BE-EF-00-11";
    expected = false;
  };

  # ----- validFixedIp -----

  testIpGatewayRejected = {
    expr = validFixedIp "172.16.0.1";
    expected = false;
  };

  testIpNetworkRejected = {
    expr = validFixedIp "172.16.0.0";
    expected = false;
  };

  testIpLowBound = {
    expr = validFixedIp "172.16.0.2";
    expected = true;
  };

  testIpHighBound = {
    expr = validFixedIp "172.16.0.254";
    expected = true;
  };

  testIpBroadcastRejected = {
    expr = validFixedIp "172.16.0.255";
    expected = false;
  };

  testIpWrongSubnet = {
    expr = validFixedIp "172.16.1.5";
    expected = false;
  };

  testIpOutsideClassB = {
    expr = validFixedIp "10.0.0.5";
    expected = false;
  };

  # ----- fixedIpsErrors -----

  testErrorsEmpty = {
    expr = fixedIpsErrors { };
    expected = [ ];
  };

  testErrorsValid = {
    expr = fixedIpsErrors {
      "DE:AD:BE:EF:00:11" = "172.16.0.10";
      "DE:AD:BE:EF:00:12" = "172.16.0.11";
    };
    expected = [ ];
  };

  testErrorsBadMac = {
    expr = fixedIpsErrors {
      "nope" = "172.16.0.10";
    };
    expected = [ ''network.fixedIps: invalid MAC address "nope".'' ];
  };

  testErrorsOutOfRange = {
    expr = fixedIpsErrors {
      "DE:AD:BE:EF:00:11" = "172.16.0.1";
    };
    expected = [
      "network.fixedIps: DE:AD:BE:EF:00:11 -> 172.16.0.1 is outside 172.16.0.2-172.16.0.254."
    ];
  };

  # Same IP on two MACs: one dedup'd duplicate message.
  testErrorsDuplicateIp = {
    expr = fixedIpsErrors {
      "DE:AD:BE:EF:00:11" = "172.16.0.10";
      "DE:AD:BE:EF:00:12" = "172.16.0.10";
    };
    expected = [ "network.fixedIps: 172.16.0.10 is assigned to more than one MAC." ];
  };
}
