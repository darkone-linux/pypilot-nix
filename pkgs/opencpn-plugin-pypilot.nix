# opencpn-plugin-pypilot — OpenCPN plugin interfacing the pypilot autopilot.
#
# Upstream uses a multi-pass CMake (configure → tarball). In Nix we run with
# BUILD_TYPE=tarball from the start, build the pypilot_pi target, and install
# artifacts manually to skip the tarball post-processing.

{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  gettext,
  wxwidgets_3_2,
  libGLU,
  libGL,
}:

let
  # opencpn-libs at the commit pinned by pypilot_pi's .gitmodules.
  opencpnLibs = fetchFromGitHub {
    owner = "OpenCPN";
    repo = "opencpn-libs";
    rev = "6a29da61ff17184e7c5a4eb9b883996a80a60fd5";
    hash = "sha256-iSQU4ZJCznXeQ/f+k0Vp+59EKqvXqg1QijQiMKrgI58=";
  };
in
stdenv.mkDerivation (_finalAttrs: {
  pname = "opencpn-plugin-pypilot";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "pypilot";
    repo = "pypilot_pi";
    rev = "1f53b4d6ef5bf8fcb151c4540ae82d4fa2edeaad";
    hash = "sha256-w/kHPVpym2meofs5kR6TjoJ6M+MV25zbMP/t3JQgjH4=";
  };

  postPatch = ''
    # opencpn-libs is a git submodule; replace with pre-fetched copy.
    rm -rf opencpn-libs
    cp -r ${opencpnLibs} opencpn-libs
    chmod -R +w opencpn-libs
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    gettext
  ];

  buildInputs = [
    wxwidgets_3_2
    libGLU
    libGL
  ];

  cmakeFlags = [
    "-DBUILD_TYPE=tarball"
    # CMake ≥4 drops compat with cmake_minimum_required <3.5;
    # libs/wxservdisc still ships CMake 3.0.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  # pypilot_pi is EXCLUDE_FROM_ALL per the template; build it explicitly.
  buildPhase = ''
    runHook preBuild
    cmake --build . --target pypilot_pi -- -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  # The upstream cmake creates a custom tarball-install target that reconfigures
  # cmake with CMAKE_INSTALL_PREFIX=app/files.  To avoid that override we
  # install the built artifacts directly.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/opencpn $out/share/opencpn/plugins/pypilot

    # Locate the built shared library (cmake build directory).
    find . -name "libpypilot_pi.so" -exec cp -t $out/lib/opencpn {} +

    # Data files (boat SVGs, toolbar icon) live in the source root.
    if [ -d "$src/data" ]; then
      cp -r "$src/data"/* $out/share/opencpn/plugins/pypilot/
    fi

    runHook postInstall
  '';

  meta = {
    description = "OpenCPN plugin to control and configure the pypilot autopilot";
    homepage = "https://github.com/pypilot/pypilot_pi";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
