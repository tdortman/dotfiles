{
  fetchurl,
  callPackage,
}:

let
  version = "0.7.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-Mwovsu+IkNre2RCE5b/SnfpBHjOisnwBrDueUg/5jZ8=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
