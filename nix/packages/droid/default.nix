{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  patchelf,
  makeWrapper,
  ripgrep,
  xdg-utils,
}:

let
  system = stdenvNoCC.hostPlatform.system;

  version = "0.102.0";
  hashes = {
    "x86_64-linux" = "sha256-i32N/04Hkm0SyXmr9aGe5a9HFI2oEkiMgwRANBWFlaA=";
    "aarch64-linux" = "sha256-jnyhD/S4MAJLRBRr4KNolRXo0hTsAF6tqU4922h19I0=";
    "x86_64-darwin" = "sha256-j2aGyAi0iOjWS6TbIeHc00Jb6TLjY58siHPvEkJ5L0s=";
    "aarch64-darwin" = "sha256-iFCSDXLIF1MG2X/4wz2Xy6pDGNZfQZZy5U9HRjE4tlg=";
  };

  platformPath =
    {
      x86_64-linux = "linux/x64";
      aarch64-linux = "linux/arm64";
      x86_64-darwin = "darwin/x64";
      aarch64-darwin = "darwin/arm64";
    }
    .${system} or (throw "droid: unsupported system ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "droid";
  inherit version;

  src = fetchurl {
    url = "https://downloads.factory.ai/factory-cli/releases/${version}/${platformPath}/droid";
    hash = hashes.${system} or (throw "droid: missing hash for system ${system}");
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ patchelf ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/droid

    makeWrapper $out/libexec/droid $out/bin/droid \
      --prefix PATH : ${
        lib.makeBinPath ([ ripgrep ] ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ xdg-utils ])
      }

    runHook postInstall
  '';

  postFixup = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} $out/libexec/droid
  '';

  meta = {
    description = "Factory's AI-powered coding agent for autonomous software development";
    homepage = "https://factory.ai";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames hashes;
    maintainers = with lib.maintainers; [ codgician ];
    mainProgram = "droid";
  };
}
