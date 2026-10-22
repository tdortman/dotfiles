{
  fetchurl,
  callPackage,
}:

let
  version = "0.9.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-j1B4AulxsWr6G23FZTF+swiF/7Kuwul206HdqkfFKdQ=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
