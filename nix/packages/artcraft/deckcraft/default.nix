{
  fetchurl,
  callPackage,
}:

let
  version = "0.13.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-cR7AlbWQ+8uqq8jFklqDUN6pjukxq3tE1Ir2iy5h9RQ=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
