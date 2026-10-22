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
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-+yuDAjDjICoe4Y7CDj9tJQ0naxZdeIEeg+tqdXJfnOI=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
