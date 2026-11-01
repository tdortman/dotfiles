{
  fetchurl,
  callPackage,
}:

let
  version = "0.13.2";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-bPT8wDCi1PuvM0+dbGDXPCof3uKmlRwGfl+hFf4Qc48=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
