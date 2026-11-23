{
  fetchurl,
  callPackage,
}:

let
  version = "0.22.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-qJk/nuluh6zOz5CvQib/YKhLnheHrp/Y+kj/4Tlrw14=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
