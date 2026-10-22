{
  fetchurl,
  callPackage,
}:

let
  version = "0.11.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-Da1dSyH8j9EZLouFTTjcwlf65mga4X8Q8bP0HoRIj08=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
