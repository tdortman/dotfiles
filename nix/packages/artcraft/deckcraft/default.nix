{
  fetchurl,
  callPackage,
}:

let
  version = "0.12.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-SkENPKpCPoc9Dcq1HJjgZYj1W9/PA+nB6RQJqGwI3j4=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
