{
  fetchurl,
  callPackage,
}:

let
  version = "0.15.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-uqzxgVgSSrw9RdxEhb/Hel1xf4CsULgGk7ZQHCZpjl0=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
