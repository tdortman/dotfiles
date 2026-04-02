{
  lib,
  stdenv,
  fetchFromGithub,
  ...
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "package";
  version = "0.1.0";

  src = fetchFromGithub {
    owner = "tdortman";
    repo = "package";
    rev = "v${finalAttrs.version}";
    hash = "";
  };

  buildInputs = [ ];
  nativeBuildInputs = [ ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r bin $out/bin

    runHook postInstall
  '';

  meta = {
    description = "Package";
    homepage = "https://github.com/tdortman/package";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "package";
    platforms = [ "x86_64-linux" ];
  };
})
