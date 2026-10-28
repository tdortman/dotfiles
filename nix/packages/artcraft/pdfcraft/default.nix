{
  fetchurl,
  callPackage,
}:

let
  version = "0.15.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-sWehjGCnsynwWlu/l+Mtxniq0/jVhm2OQ3j/JCc/gxM=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
