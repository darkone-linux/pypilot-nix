# Pure helpers for the serial-device registry (navigation/signalk modules).
#
# Kept out of the module system so they stay unit-testable in isolation
# (tests/unit/lib/serial_test.nix). They operate on plain attrsets, not module
# values; a `match` is `{ vendorId; productId; serial; port }` (any may be null).

{ lib }:
rec {

  # Both set or both null — USB id-pair completeness. Used by the gps/motor
  # assertions and inside serialMatchValid.
  pairComplete = a: b: (a == null) == (b == null);

  # A device match is valid iff exactly one mode is used: a complete USB id pair
  # (serial optional) XOR a port path. A half-filled USB pair is never valid.
  serialMatchValid =
    match:
    let
      usb = match.vendorId != null && match.productId != null;
      partialUsb = !(pairComplete match.vendorId match.productId);
    in
    !partialUsb && (usb != (match.port != null));

  # Deduplicate registry entries by `.name`, keeping the first occurrence and
  # preserving order: several udev matches may target one /dev symlink, but
  # Signal K wants a single provider per device.
  uniqueByName =
    entries:
    (lib.foldl'
      (
        acc: e:
        if lib.elem e.name acc.seen then
          acc
        else
          {
            seen = acc.seen ++ [ e.name ];
            out = acc.out ++ [ e ];
          }
      )
      {
        seen = [ ];
        out = [ ];
      }
      entries
    ).out;
}
