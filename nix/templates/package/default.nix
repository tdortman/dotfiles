{
  lib,
  fetchFromGithub,
  stdenv,
  ...
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "package";
  version = "0.1.0";

  src = fetchFromGithub {
    hash = "";
    owner = "tdortman";
    repo = "package";
    rev = "v${finalAttrs.version}";
  };

  buildInputs = [ ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r bin $out/bin

    runHook postInstall
  '';

  nativeBuildInputs = [ ];

  meta = {
    description = "Package";
    homepage = "https://github.com/tdortman/package";
    license = lib.licenses.gpl3Only;
    mainProgram = "package";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
})
