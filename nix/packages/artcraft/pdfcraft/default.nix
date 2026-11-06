{
  fetchurl,
  callPackage,
}:

let
  version = "0.18.2";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-MjutezczkgdkYeLK1dtjsi9HoDK6AFpsSjXzSD0F2uQ=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
