{
  fetchurl,
  callPackage,
}:

let
  version = "0.16.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-MluX8Vu/UyYooxdqnBcUinF18+Txm5MT3jI6tRNgl1I=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
