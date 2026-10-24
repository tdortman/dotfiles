{
  fetchurl,
  callPackage,
}:

let
  version = "0.15.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-tiK+QDVVEwVvgVKv6JXQoFwbw8NEoCf3cqmhL6PRwiM=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
