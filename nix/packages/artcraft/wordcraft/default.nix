{
  fetchurl,
  callPackage,
}:

let
  version = "0.5.0";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-mUuzdkee9tdnNc9AKeXvPC1SqFpMms3is3wzsZxXAgM=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
