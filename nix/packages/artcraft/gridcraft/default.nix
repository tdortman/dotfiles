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
    url = "https://github.com/storytold/gridcraft/releases/download/v${version}/gridcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-FOk3RVW8bS2cW8QbsxFQvGoctrToPVq0Fj/V12EbBhg=";
  };

  description = "Open-source, clean-room spreadsheet in the style of Microsoft Excel";
  name = "gridcraft";
}
