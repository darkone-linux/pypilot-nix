# Tests for lib/serial.nix — serial-device registry helpers.
# Run with: just test  (or: nix-unit --flake .#libTests)

{ navLib }:
let
  inherit (navLib.serial) pairComplete serialMatchValid uniqueByName;

  # A full match record (all four keys present, as the module guarantees).
  match =
    {
      vendorId ? null,
      productId ? null,
      serial ? null,
      port ? null,
    }:
    {
      inherit
        vendorId
        productId
        serial
        port
        ;
    };
in
{

  # ----- pairComplete -----

  testPairBothNull = {
    expr = pairComplete null null;
    expected = true;
  };

  testPairBothSet = {
    expr = pairComplete "1546" "01a7";
    expected = true;
  };

  testPairFirstOnly = {
    expr = pairComplete "1546" null;
    expected = false;
  };

  testPairSecondOnly = {
    expr = pairComplete null "01a7";
    expected = false;
  };

  # ----- serialMatchValid -----

  testMatchUsbOnly = {
    expr = serialMatchValid (match {
      vendorId = "27c5";
      productId = "0402";
    });
    expected = true;
  };

  testMatchUsbWithSerial = {
    expr = serialMatchValid (match {
      vendorId = "27c5";
      productId = "0402";
      serial = "793379380P51";
    });
    expected = true;
  };

  testMatchPortOnly = {
    expr = serialMatchValid (match {
      port = "fe201000.serial:0.0";
    });
    expected = true;
  };

  testMatchNeither = {
    expr = serialMatchValid (match { });
    expected = false;
  };

  testMatchPartialVendor = {
    expr = serialMatchValid (match {
      vendorId = "27c5";
    });
    expected = false;
  };

  testMatchPartialProduct = {
    expr = serialMatchValid (match {
      productId = "0402";
    });
    expected = false;
  };

  testMatchUsbAndPort = {
    expr = serialMatchValid (match {
      vendorId = "27c5";
      productId = "0402";
      port = "fe201000.serial:0.0";
    });
    expected = false;
  };

  testMatchPartialUsbAndPort = {
    expr = serialMatchValid (match {
      vendorId = "27c5";
      port = "fe201000.serial:0.0";
    });
    expected = false;
  };

  # ----- uniqueByName -----

  testUniqueEmpty = {
    expr = uniqueByName [ ];
    expected = [ ];
  };

  testUniqueSingle = {
    expr = uniqueByName [ { name = "gps0"; } ];
    expected = [ { name = "gps0"; } ];
  };

  testUniqueDistinct = {
    expr = uniqueByName [
      { name = "gps0"; }
      { name = "ais0"; }
    ];
    expected = [
      { name = "gps0"; }
      { name = "ais0"; }
    ];
  };

  # Duplicate name: first occurrence kept (id 1), order preserved.
  testUniqueKeepsFirstAndOrder = {
    expr = uniqueByName [
      {
        name = "ais0";
        id = 1;
      }
      { name = "gps0"; }
      {
        name = "ais0";
        id = 2;
      }
    ];
    expected = [
      {
        name = "ais0";
        id = 1;
      }
      { name = "gps0"; }
    ];
  };
}
