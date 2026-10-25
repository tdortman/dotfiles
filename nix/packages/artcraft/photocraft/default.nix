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
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-fBfzYz6/favydiji0mN9kYx8KlsWO4uQNHp4rN32Ngg=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
