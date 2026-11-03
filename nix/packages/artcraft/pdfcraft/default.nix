{
  fetchurl,
  callPackage,
}:

let
  version = "0.18.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-yzZlzEXMeqa6AchouffGncTYAL71LUHP/qi/UDfE620=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
