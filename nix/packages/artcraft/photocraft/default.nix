{
  fetchurl,
  callPackage,
}:

let
  version = "0.20.2";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-CeAT1o2DE+sLHNbyRhL1tf0NmT//46fBLOzf5c0TGkY=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
