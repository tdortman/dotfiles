{
  fetchurl,
  callPackage,
}:

let
  version = "0.16.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-TFwiMYa9HpT+2f7a88v3eprJbdRaMr82RI/AIwZvE98=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
