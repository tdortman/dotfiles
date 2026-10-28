{
  fetchurl,
  callPackage,
}:

let
  version = "0.17.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-Uln5xCjI7jR4w1UA7OmHE1Ycr8BQ5MnrNUpQUPNusrg=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
