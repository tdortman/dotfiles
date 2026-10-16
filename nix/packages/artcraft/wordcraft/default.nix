{
  fetchurl,
  callPackage,
}:

let
  version = "0.7.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-YwCfiOPbrqcKwTePq8hVWuFHddMoKRdcXaJVGr4Dky8=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
