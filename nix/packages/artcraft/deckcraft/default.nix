{
  fetchurl,
  callPackage,
}:

let
  version = "0.11.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/deckcraft/releases/download/v${version}/deckcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-e/V6EKT892c+y2abZODlRUdXgO8+Tua/YDrrAPVE5pw=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft PowerPoint";
  name = "deckcraft";
}
