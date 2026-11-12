{
  fetchurl,
  callPackage,
}:

let
  version = "0.18.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-W659VWZjhiRBHvlo8lMqszWNwoCIQURYPkl8VjHbiiY=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
