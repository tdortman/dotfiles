{
  lib,
  stdenv,
  fetchFromGitHub,
  bun,
  cargo,
  nodejs,
  rustPlatform,
  rustc,
  writableTmpDirAsHomeHook,
  pkg-config,
  libx11,
  libxcb,
  libxkbfile,
  libxkbcommon,
  wayland,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "oh-my-pi";
  version = "15.2.1";

  src = fetchFromGitHub {
    owner = "can1357";
    repo = "oh-my-pi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-fztQJrhDG5ZbTlgqoHA96eCgwYm5WIna3mAPlCDWYLM=";
  };

  nodeModules = stdenv.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      find . -type d -name node_modules -exec cp -R --parents {} $out \;

      runHook postInstall
    '';

    outputHash = "sha256-7gcURFQrvn8CBfQEazy6nId+n5fPpx+u7cOMgpsHMLc=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  cargoRoot = ".";
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${finalAttrs.src}/Cargo.lock";
  };

  nativeBuildInputs = [
    bun
    cargo
    nodejs
    rustPlatform.cargoSetupHook
    pkg-config
    rustc
    writableTmpDirAsHomeHook
  ];

  buildInputs = [
    libx11
    libxcb
    libxkbfile
    libxkbcommon
    wayland
  ];

  postPatch = ''
    # this is apparently due to some @aws- packages
    substituteInPlace packages/utils/package.json \
      --replace-fail '"bun": ">=1.3.14"' '"bun": ">=1.3.13"'

    cp -R ${finalAttrs.nodeModules}/. .
    chmod -R +w node_modules
    patchShebangs --build node_modules
  '';

  buildPhase = ''
    runHook preBuild

    bun --cwd=packages/coding-agent run generate-docs-index
    bun --cwd=packages/natives run build
    bun --cwd=packages/coding-agent scripts/build-binary.ts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 packages/coding-agent/dist/omp $out/bin/omp

    runHook postInstall
  '';

  # This would fuck with bun's compiled executable and result in the binary
  # just being detected as bun instead of bun as a runtime for the actual embedded code
  dontStrip = true;

  meta = {
    description = "AI coding agent for the terminal";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "omp";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.linux;
  };
})
