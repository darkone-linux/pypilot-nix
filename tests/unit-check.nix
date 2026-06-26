# Flake-check wrapper around the pure unit suites (tests/unit).
#
# nix-unit (just test) reads the suites directly; here the same files run through
# lib.runTests so `nix flake check` fails on regression too. nix-unit groups
# tests one level deep, runTests is flat AND only runs attrs whose name starts
# with "test" — so flatten to `test_<suite>_<leaf>`, keeping that prefix.

{ pkgs }:
let
  inherit (pkgs) lib;

  suites = import ./unit { inherit lib; };

  flat = lib.concatMapAttrs (
    suite: tests: lib.mapAttrs' (n: v: lib.nameValuePair "test_${suite}_${n}" v) tests
  ) suites;

  failures = lib.runTests flat;

  report = lib.concatMapStringsSep "\n" (
    f:
    "  ${f.name}: expected ${lib.generators.toPretty { multiline = false; } f.expected}, "
    + "got ${lib.generators.toPretty { multiline = false; } f.result}"
  ) failures;
in
if failures == [ ] then
  pkgs.runCommand "navigation-unit-tests" { } "touch $out"
else
  throw "navigation unit tests failed:\n${report}"
