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

      llvmPkgs = pkgs.llvmPackages_22;
      cudaPkgs = pkgs.cudaPackages_13_2;

      rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

      buildInputs = with pkgs; [
        stdenv.cc.cc.lib
        cudaPkgs.cudatoolkit
      ];

      nativeBuildInputs = [
        rust-toolchain
        llvmPkgs.llvm
        llvmPkgs.clang
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        inherit buildInputs nativeBuildInputs;

        env = {
          LD_LIBRARY_PATH = "${
            pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)
          }:/run/opengl-driver/lib";

          CUDA_HOME = cudaPkgs.cudatoolkit;
          LIBCLANG_PATH = "${llvmPkgs.libclang.lib}/lib";
          CPATH = "${cudaPkgs.cudatoolkit}/include";
          LIBNVJITLINK_PATH = "${cudaPkgs.libnvjitlink.lib}/lib/libnvJitLink.so";
          CUDA_OXIDE_LLC = "${llvmPkgs.llvm}/bin/llc";

          RUSTFLAGS = "-L /run/opengl-driver/lib";
        };
      };
    };
}
