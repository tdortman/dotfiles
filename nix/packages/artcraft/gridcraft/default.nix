{
  fetchurl,
  callPackage,
}:

let
  version = "0.10.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-t4ooYFzTRZT8Nd/BrTapJAVFcaE4JiX7dQb9cM37kZc=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
