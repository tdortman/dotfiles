let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  rustOverlay = fetchTarball "https://github.com/oxalica/rust-overlay/archive/master.tar.gz";

  pkgs = import nixpkgs {
    overlays = [ (import rustOverlay) ];
    config.allowUnfree = true;
  };

  rust-toolchain = pkgs.rust-bin.stable.latest.default.override {
    extensions = [ "rust-src" ];
  };

  buildInputs = with pkgs; [
    stdenv.cc.cc.lib
  ];

  nativeBuildInputs = [
    rust-toolchain
    pkgs.rust-analyzer
    pkgs.mold-unwrapped
    pkgs.llvmPackages_22.clang
  ];
in

pkgs.mkShell {
  inherit buildInputs nativeBuildInputs;

  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)}";
}
