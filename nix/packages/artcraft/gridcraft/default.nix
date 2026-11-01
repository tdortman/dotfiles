{
  fetchurl,
  callPackage,
}:

let
  version = "0.14.2";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-nIFTt2MK373vgCGqm5guHvGHts8nzSIzKAz68LpqGEI=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
