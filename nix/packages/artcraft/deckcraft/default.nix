{
  fetchurl,
  callPackage,
}:

let
  version = "0.9.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-UxtMjNQ0ynZ+8h2g1E4JlmSvXV2WiwOLyPkncX+PqPE=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
