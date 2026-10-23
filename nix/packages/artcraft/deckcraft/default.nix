{
  fetchurl,
  callPackage,
}:

let
  version = "0.10.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-VGYW6yMAzo77ILRKU+YKv+a5bXGsYGtFKjb9Icax/yg=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
