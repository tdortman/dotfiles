{
  fetchurl,
  callPackage,
}:

let
  version = "0.12.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-zZq9DuehG5ha8cFXFlMzLJYHfl3MSLXhh7VcgvR1oz4=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
