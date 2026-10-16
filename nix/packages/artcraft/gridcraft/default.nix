{
  fetchurl,
  callPackage,
}:

let
  version = "0.7.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-wBvC3EKVVW9TgQ3+1KhaP1g4hVLBV6ED4QYmwGmznhw=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
