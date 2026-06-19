# signalk-server — Signal K marine data hub (Node.js).
#
# Built from the published npm tarball, which is the project's recommended
# install method (`npm install -g signalk-server`). Unlike a build from the
# GitHub monorepo, the tarball ships compiled JS and pulls the prebuilt admin
# UI (@signalk/server-admin-ui) and webapp plugins as registry dependencies, so
# there is no TypeScript/webapp build step and none of the source tree's legacy
# native-build pain (node-sass, mdns).
#
# npm tarballs carry no lockfile, so one generated from this exact version's
# package.json is vendored alongside this file.

{
  lib,
  buildNpmPackage,
  fetchurl,
  python3,
  pkg-config,
  systemd,
}:

buildNpmPackage rec {
  pname = "signalk-server";
  version = "2.28.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/signalk-server/-/signalk-server-${version}.tgz";
    hash = "sha256-KmK4XKqJWN6MxFqhoKhEYIkAUgWAmfV7lz6CSMXXZO4=";
  };

  npmDepsHash = "sha256-RbOkj/U0H0cgPBvzR0UlBFg83T7QINN+9dyhBM0i7l0=";

  # The tarball is already compiled; only dependencies need installing.
  dontNpmBuild = true;

  postPatch = ''
    cp ${./signalk-server-package-lock.json} package-lock.json
    echo "package-lock=true" > .npmrc
  '';

  # serialport's native binding falls back to node-gyp (python + pkg-config) if
  # no prebuild matches; systemd provides libudev for it at build and run time.
  nativeBuildInputs = [
    python3
    pkg-config
  ];
  buildInputs = [ systemd ];

  meta = {
    description = "Signal K server: a marine data hub for boats";
    homepage = "https://signalk.org/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "signalk-server";
  };
}
