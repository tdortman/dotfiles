{
  fetchurl,
  callPackage,
}:

let
  version = "0.9.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-kTAMFIWtcQg5YEsIVTHJDnesfr2yowJZMJrXSvz9uQ0=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
