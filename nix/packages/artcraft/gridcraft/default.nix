{
  fetchurl,
  callPackage,
}:

let
  version = "0.19.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-jZe7otW7AP1p7VUGSFLB/ZFN5A1ezVXKAcjfgbgolG0=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
