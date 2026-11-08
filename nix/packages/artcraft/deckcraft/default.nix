{
  fetchurl,
  callPackage,
}:

let
  version = "0.16.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-7tVysvYjldD1z+JGpygYllHpXk7N9MPgrYe3ejgx4IY=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
