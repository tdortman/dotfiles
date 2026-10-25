{
  fetchurl,
  callPackage,
}:

let
  version = "0.12.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-HBdQ3W0mN2z4yK8itG3A7T2NXLsRXlVfD8fQz3qa6po=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
