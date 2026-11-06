{
  fetchurl,
  callPackage,
}:

let
  version = "0.15.2";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-Nm5U4jW0Yxd5wMeMB3eogN5REWPekTCreM5ZWD96C5o=";
  };

  description = "Open-source, clean-room reimplementation of Microsoft Word";
  name = "wordcraft";
}
