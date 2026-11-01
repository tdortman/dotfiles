{
  fetchurl,
  callPackage,
}:

let
  version = "0.18.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-S4rI4RRqyal+e/3vFrJn1Tlqd4Cf1OIym4Pa14CGV08=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
