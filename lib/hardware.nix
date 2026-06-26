# Pure helpers for the hardware HAT selector.
#
# Kept out of the module system so they can be unit-tested in isolation
# (tests/unit/lib/hardware_test.nix) without evaluating a full nixosConfiguration.
# A claim is `{ owner; pins }`: the device name and the BCM GPIOs it drives.

{ lib }:
rec {

  # Map every claimed BCM pin (string key) to the owners that claim it.
  gpioOwnersByPin =
    claims:
    lib.foldl' (
      acc: claim:
      lib.foldl' (
        a: pin: a // { "${toString pin}" = (a."${toString pin}" or [ ]) ++ [ claim.owner ]; }
      ) acc claim.pins
    ) { } claims;

  # Pins claimed by more than one owner: { "<pin>" = [ owners ]; }.
  gpioConflicts =
    claims: lib.filterAttrs (_pin: owners: lib.length owners > 1) (gpioOwnersByPin claims);

  # null when no conflict; otherwise the assertion message naming the contending
  # devices and the pins they fight over.
  gpioConflictMessage =
    claims:
    let
      conflicts = gpioConflicts claims;
      contendedPins = lib.attrNames conflicts;
      contendingOwners = lib.unique (lib.concatLists (lib.attrValues conflicts));
    in
    if conflicts == { } then
      null
    else
      "services.navigation.hardware: ${lib.concatStringsSep ", " contendingOwners} "
      + "claim the same BCM GPIO(s) ${lib.concatStringsSep ", " contendedPins}; "
      + "enable only one of these HATs/modules.";
}
