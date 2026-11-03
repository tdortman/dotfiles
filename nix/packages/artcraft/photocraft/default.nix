{
  fetchurl,
  callPackage,
}:

let
  version = "0.20.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-OYeH1Y/kaRnpnJ9W41VFVJ7wqqsAf4aakr7/fZ/lIjQ=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
