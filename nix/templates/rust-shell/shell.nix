let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
  rustOverlay = fetchTarball "https://github.com/oxalica/rust-overlay/archive/master.tar.gz";

  pkgs = import nixpkgs {
    config.allowUnfree = true;
    overlays = [ (import rustOverlay) ];
  };

  rust-toolchain = pkgs.rust-bin.stable.latest.default.override {
    extensions = [ "rust-src" ];
  };

  buildInputs = with pkgs; [
    stdenv.cc.cc.lib
  ];

  nativeBuildInputs = [
    pkgs.llvmPackages_22.clang
    pkgs.mold-unwrapped
    pkgs.rust-analyzer
    rust-toolchain
  ];
in

pkgs.mkShell {
  inherit buildInputs nativeBuildInputs;
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)}";
}
