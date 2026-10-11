{
  fetchurl,
  callPackage,
}:

let
  version = "0.5.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-wmSMYHH2MezGY5zmt9YPaO7YPd6rprFVmwfFBGhjEXw=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
