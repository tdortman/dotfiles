let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  pkgs = import nixpkgs {
    config.allowUnfree = true;
  };

  buildInputs = with pkgs; [
  ];

  nativeBuildInputs = with pkgs; [
  ];
in

pkgs.mkShell {
  inherit buildInputs nativeBuildInputs;
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)}";
}
