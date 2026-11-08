{
  fetchurl,
  callPackage,
}:

let
  version = "0.19.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/pdfcraft/releases/download/v${version}/pdfcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-NleqQP4UbUr0D6sFB8l/buLGzlupk4VnGUQ5vjM1uos=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Acrobat";
  name = "pdfcraft";
}
