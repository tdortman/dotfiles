{
  fetchurl,
  callPackage,
}:

let
  version = "0.8.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-P0/V3dmYAqPTSUdMYc89q9H7cZjqDfANJMwxBRa9HCo=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
