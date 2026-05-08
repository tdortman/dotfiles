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
        overlays = [ rust-overlay.overlays.default ];
        config.allowUnfree = true;
      };

      rust-toolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" ];
      };

      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
      ];

      nativeBuildInputs = with pkgs; [
        rust-toolchain
        rust-analyzer
        mold-unwrapped
        llvmPackages_22.clang
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        inherit buildInputs nativeBuildInputs;

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs);
      };
    };
}
