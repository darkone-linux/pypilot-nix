# AIS-catcher — AIS receiver/decoder for RTL-SDR (and other SDR) hardware.
#
# Marine use: decode AIS from an RTL-SDR dongle and forward NMEA0183 over UDP to
# Signal K (:10110). The many optional SDR backends and the embedded web UI are
# turned off — Signal K already provides the UI, and only RTL-SDR is wired here.
#
# Not yet in nixpkgs; packaged locally with the intent to upstream it.

{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,

  # rtl-sdr-blog fork, not osmocom mainline: mainline librtlsdr lacks the R828D
  # tuner init the RTL-SDR Blog v4 needs — it enumerates but decodes nothing.
  rtl-sdr-blog,
  libusb1,
  zlib,
  openssl,
  soxr,
  libsamplerate,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ais-catcher";
  version = "0.70";

  src = fetchFromGitHub {
    owner = "jvde-github";
    repo = "AIS-catcher";
    rev = "v${finalAttrs.version}";
    hash = "sha256-YDkqIoW3DDwUfAJftvfnmsIQYCq9ujYrB8RvZRiIexg=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    rtl-sdr-blog
    libusb1
    zlib
    openssl
    soxr
    libsamplerate
  ];

  cmakeFlags = [
    (lib.cmakeBool "RTLSDR" true)
    (lib.cmakeBool "ZLIB" true)
    (lib.cmakeBool "OPENSSL" true)
    (lib.cmakeBool "SOXR" true)
    (lib.cmakeBool "SAMPLERATE" true)

    # Backends/features not provided here (proprietary or unneeded aboard).
    (lib.cmakeBool "SOAPYSDR" false)
    (lib.cmakeBool "AIRSPY" false)
    (lib.cmakeBool "AIRSPYHF" false)
    (lib.cmakeBool "SDRPLAY" false)
    (lib.cmakeBool "HACKRF" false)
    (lib.cmakeBool "HYDRASDR" false)
    (lib.cmakeBool "ZMQ" false)
    (lib.cmakeBool "PSQL" false)
    (lib.cmakeBool "SQLITE" false)
    (lib.cmakeBool "NMEA2000" false)
    (lib.cmakeBool "WEBVIEWER" false)
  ];

  # Upstream ships no install rule; place the single binary by hand.
  installPhase = ''
    runHook preInstall
    install -Dm755 AIS-catcher $out/bin/AIS-catcher
    runHook postInstall
  '';

  meta = {
    description = "AIS receiver and decoder for RTL-SDR and other SDR hardware";
    homepage = "https://github.com/jvde-github/AIS-catcher";
    license = lib.licenses.gpl3Plus;
    mainProgram = "AIS-catcher";
    platforms = lib.platforms.linux;
  };
})
