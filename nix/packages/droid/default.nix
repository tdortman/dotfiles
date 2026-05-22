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

  version = "0.132.0";
  hashes = {
    "x86_64-linux" = "sha256-ykKFhNpSSg3FrbcFpoLXqDLB1tEqW7docYpWWpfqVlQ=";
    "aarch64-linux" = "sha256-u6Wo9gEcZQLZmea98oe2FNy4kKwhBS8rS7ZloT+zPwM=";
    "x86_64-darwin" = "sha256-WFagmt7UcQp7us0xQFtE7GvCs+Gmp2REImI66vDMoio=";
    "aarch64-darwin" = "sha256-AGnAHCyqe+9ao6quqEZ4r/USMgLPB65OSBuz0RGysy0=";
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
