{
  lib,
  stdenv,
  autoPatchelfHook,
  makeWrapper,
  requireFile,
  vulkan-loader,
  wayland,
  libxkbcommon,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "delta";
  version = "0.1.1-nightly.20260826.18";

  src = requireFile {
    url = "https://delta.dev/download";
    hash = "sha256-RLxIxbJWjYSSTz6k0VzFM8QMH07A5SQXYz2z9WGcrxQ=";
    name = "delta-linux-x86_64.tar.gz";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r bin lib share $out/

    runHook postInstall
  '';

  runtimeDependencies = [
    vulkan-loader
    wayland
    libxkbcommon
  ];

  meta = {
    description = "AI-native code editor";
    homepage = "https://delta.dev";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "delta";
  };
})
