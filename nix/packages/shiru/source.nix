{
  lib,
  stdenv,
  fetchFromGitHub,
  pnpm_10,
  makeWrapper,
  nodejs,
  python3,
  libxcrypt,
  unzip,
  fetchzip,
  autoPatchelfHook,
  electron,
  pnpmConfigHook,
  fetchPnpmDeps,

  pango,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libgbm,
  expat,
  libxcb,
  libxkbcommon,
  systemd,
  alsa-lib,
  at-spi2-atk,
  nspr,
  nss,
  cups,
  gtk3,
  libGL,
  glib,
}:

let
  electronVersion = "39.2.7";
  electronHeaders = fetchzip {
    url = "https://www.electronjs.org/headers/v${electronVersion}/node-v${electronVersion}-headers.tar.gz";
    hash = "sha256-Yrk7++Ttjm42J0TXTDxyUJC5nVSlNMDIt9/PrZaBsxA=";
  };

  electronDist = fetchzip {
    url = "https://github.com/electron/electron/releases/download/v${electronVersion}/electron-v${electronVersion}-linux-x64.zip";
    hash = "sha256-zeGTv504UUUZETelo5lZHAMUgSFloRRuUxpzP0IezuA=";
    stripRoot = false;
  };
in

stdenv.mkDerivation (finalAttrs: {
  pname = "shiru";
  version = "6.5.1";

  src = fetchFromGitHub {
    owner = "RockinChaos";
    repo = "Shiru";
    rev = "v${finalAttrs.version}";
    hash = "sha256-dqXpX4pLF3EjoTrjofOPTO39EGU/2JyfS3+slwCR4xU=";
  };

  buildInputs = [
    stdenv.cc.cc.lib
    libxcrypt
    pango
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libgbm
    expat
    libxcb
    libxkbcommon
    systemd
    alsa-lib
    at-spi2-atk
    nspr
    nss
    cups.lib
    gtk3
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    pnpmConfigHook
    nodejs
    python3
    makeWrapper
    unzip
    pnpm_10
  ];

  runtimeInputs = [
    glib
    libGL
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-38z1Lrs2e7wspwg7ftuisL5n4qhqfcidjash1l9XprY=";
  };

  buildPhase = ''
    runHook preBuild

    cd electron
    pnpm install

    export npm_config_nodedir=${electronHeaders}
    export npm_config_python=${python3}/bin/python3

    pnpm run web:build

    ./node_modules/.bin/electron-builder \
      --linux dir \
      -c.electronDist=${electronDist} \
      -c.electronVersion=${electronVersion}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/shiru
    cp -r dist $out/dist
    cp -r dist/linux-unpacked/resources $out/share/shiru/

    makeWrapper ${electron}/bin/electron $out/bin/shiru \
      --add-flags "$out/share/shiru/resources/app.asar" \
      --add-flags "--no-sandbox"

    runHook postInstall
  '';

  meta = {
    description = "Manage your personal media library, organize your collection, and stream your content in real time, no waiting required!";
    homepage = "https://github.com/RockinChaos/Shiru";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "shiru";
    platforms = [ "x86_64-linux" ];
  };
})
