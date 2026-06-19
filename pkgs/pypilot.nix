# pypilot — free sailboat autopilot (Python + SWIG C/C++ extensions).
#
# Builds the SWIG modules linebuffer/arduino_servo/ugfx/spireader. The two git
# dependencies declared in pyproject.toml (RTIMULib, pypilot_data) are rewritten
# to plain names and satisfied by the corresponding Nix packages.

{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  swig,
  pkg-config,
  libgpiod,

  # Core runtime dependencies.
  pyserial,
  numpy,
  scipy,
  zeroconf,
  rtimulib2,
  pypilot-data,

  # HAT control head (pypilot_hat): libgpiod v2 bindings + LCD image rendering.
  gpiod,
  pillow,

  # signalk + web UI dependencies (pyproject optional groups, enabled here so
  # the daemon and its web interface are usable out of the box).
  requests,
  websocket-client,
  flask,
  gevent-websocket,
  python-socketio,
  flask-socketio,
}:

buildPythonPackage rec {
  pname = "pypilot";
  version = "0.70";

  src = fetchFromGitHub {
    owner = "pypilot";
    repo = "pypilot";
    rev = "33a12b06869ba21f854d9d2e1bca12c842421231";
    hash = "sha256-2EKTHBErpUsm1m7gHcQnQDGMvY22D9+14KEoXqAQO6M=";
  };

  pyproject = true;
  build-system = [ setuptools ];

  # swig is the binary tool here (the pyproject build-requirement of the same
  # name is the PyPI shim for it, dropped in postPatch).
  nativeBuildInputs = [
    pkg-config
    swig
  ];

  # libgpiod lets setup.py build the HAT display (ugfx) bindings with GPIO.
  buildInputs = [ libgpiod ];

  # Drop the git+https direct references so the deps resolve to Nix packages.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '"RTIMULib @ git+https://github.com/seandepagnier/RTIMULib2@master#subdirectory=Linux/python",' '"RTIMULib",' \
      --replace-fail '"pypilot_data @ git+https://github.com/pypilot/pypilot_data@1df915910725d586cb846cdca42ee445c2709ff6"' '"pypilot_data"' \
      --replace-fail 'requires = ["setuptools>=64", "swig"]' 'requires = ["setuptools>=64"]'
  '';

  # The wheel build runs build_py before build_ext, so SWIG's generated .py
  # wrappers would be missing from the package. Generate the extensions (and
  # their wrappers) in-place first so build_py picks them up.
  preBuild = ''
    python setup.py build_ext --inplace
  '';

  dependencies = [
    pyserial
    numpy
    scipy
    zeroconf
    rtimulib2
    pypilot-data
    gpiod
    pillow
    requests
    websocket-client
    flask
    gevent-websocket
    python-socketio
    flask-socketio
  ];

  # Smoke-test that the SWIG extensions load (per the test strategy, level 1).
  pythonImportsCheck = [
    "pypilot.linebuffer"
    "pypilot.arduino_servo.arduino_servo"
  ];

  meta = {
    description = "Free autopilot for sailboats, supporting SignalK and NMEA";
    homepage = "http://pypilot.org/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "pypilot";
  };
}
