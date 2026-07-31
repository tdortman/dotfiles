let
  buildInputs = with pkgs; [
  ];
  nativeBuildInputs = with pkgs; [
  ];
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
  };
in

pkgs.mkShell {
  inherit buildInputs nativeBuildInputs;
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)}";
}
