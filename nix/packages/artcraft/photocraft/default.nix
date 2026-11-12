{
  fetchurl,
  callPackage,
}:

let
  version = "0.23.1";
in
callPackage ../craft-app.nix {
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.tar.gz";
    hash = "sha256-Q4Ou9noHzDcK0lCm7WABUgXT5sRj+vP/Sw9nuBeMz8g=";
  };

  description = "Open-source, clean-room reimplementation of Adobe Photoshop";
  name = "photocraft";
}
