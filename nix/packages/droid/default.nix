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

  version = "0.109.3";
  hashes = {
    "x86_64-linux" = "sha256-NGbkHHEl6MIIUfpDOtbg2fZgb26wfMPbsQpAnQjH7gc=";
    "aarch64-linux" = "sha256-lHoi+h6fT8OmbTB9PzxaFRuoHDFOwF8Ab6X5rKyO2g0=";
    "x86_64-darwin" = "sha256-LQEGHPWltOQB+riKRUqwdadut8FX5679vRUMD802dYg=";
    "aarch64-darwin" = "sha256-l6g+NYfTX6If56NK4rwhnCXmmFQ0YuP83LHjliIe0nA=";
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
