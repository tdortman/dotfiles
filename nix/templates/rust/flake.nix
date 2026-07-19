{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ rust-overlay.overlays.default ];
      };

      rust-toolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" ];
      };

      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
      ];

      nativeBuildInputs = with pkgs; [
        llvmPackages_22.clang
        mold-unwrapped
        rust-analyzer
        rust-toolchain
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        inherit buildInputs nativeBuildInputs;
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs);
      };
    };
}
