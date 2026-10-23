{
  fetchurl,
  callPackage,
}:

let
  version = "0.13.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-WYUZ6ivHfGbKmpBiQeH+Psz3RfUGJ84829W15nWkVtM=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
