{
  fetchurl,
  callPackage,
}:

let
  version = "0.6.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-mhNuceN7RZ7VdG2+GaNkzoTPXZlcb2yYr2FH2Bg5ClM=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
