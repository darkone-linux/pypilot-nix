# canboat — NMEA2000 (CAN) analysis and conversion toolkit.
#
# Marine use: decode the boat's NMEA2000 bus into human-readable text or JSON
# (`analyzer`), bridge SocketCAN / Actisense / iKonvert gateways and replay
# captures. The companion CLI to `can-utils` for the MacArthur HAT's can0 link.
#
# Plain Makefile build (only libc/-lm), binaries land in `rel/<platform>/`; no
# upstream `make install`, so the binaries are placed with installBin.
# Not yet in nixpkgs; packaged locally with the intent to upstream it.

{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "canboat";
  version = "6.2.2";

  src = fetchFromGitHub {
    owner = "canboat";
    repo = "canboat";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ptuhp5cvMbfc2+RmdygzsegGwWgIgkgAk3NQ76j1pMw=";
  };

  nativeBuildInputs = [ installShellFiles ];

  enableParallelBuilding = true;

  # Binaries go to rel/<uname>-<arch>/; glob it so aarch64 and x86_64 both work.
  installPhase = ''
    runHook preInstall
    installBin rel/*/*
    runHook postInstall
  '';

  meta = {
    description = "NMEA2000/CAN analysis and conversion toolkit (analyzer, n2kd, …)";
    homepage = "https://github.com/canboat/canboat";
    license = lib.licenses.asl20;
    mainProgram = "analyzer";
    platforms = lib.platforms.linux;
  };
})
