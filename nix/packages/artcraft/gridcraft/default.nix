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
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-8sg+bCZEmmxFmD6QO/MsHUwwKyBC8mPq2ZUnESnHDoc=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
