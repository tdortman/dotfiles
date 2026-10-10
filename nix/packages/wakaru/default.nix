{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "wakaru";
  version = "1.13.0";

  # The npm wrapper package only re-exports this platform package, which holds
  # the self-contained binary.
  src = fetchurl {
    url = "https://registry.npmjs.org/@wakaru/cli-linux-x64/-/cli-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-sWvdLUesq+9gYWWHvowB/EdzQ5tfXXcprFESlSiGPdQ=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  # The binary links against libgcc_s from the C toolchain.
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    install -Dm755 wakaru $out/bin/wakaru

    runHook postInstall
  '';

  sourceRoot = "package";

  meta = {
    description = "JavaScript deobfuscator and unpacker";
    homepage = "https://github.com/pionxzh/wakaru";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "wakaru";
  };
})
