{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      buildInputs = with pkgs; [
        cudaToolkit
        stdenv.cc.cc.lib
      ];
      cudaPkgs = pkgs.cudaPackages_13_2;
      cudaToolkit = pkgs.symlinkJoin {
        name = "cuda-oxide-toolkit";

        paths = with cudaPkgs; [
          cuda_cudart
          cuda_gdb.bin
          cuda_nvcc
          libnvjitlink.lib
          libnvvm
        ];
      };
      llvmPkgs = pkgs.llvmPackages_22;
      nativeBuildInputs = [
        llvmPkgs.clang
        llvmPkgs.llvm
        rust-toolchain
      ];
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ rust-overlay.overlays.default ];
      };
      rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
      system = "x86_64-linux";
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        inherit buildInputs nativeBuildInputs;

        env = {
          CUDA_HOME = cudaToolkit;
          CUDA_OXIDE_LLC = "${llvmPkgs.llvm}/bin/llc";
          CUDA_TOOLKIT_PATH = cudaToolkit;

          LD_LIBRARY_PATH = "${
            pkgs.lib.makeLibraryPath (buildInputs ++ nativeBuildInputs)
          }:/run/opengl-driver/lib";

          LIBCLANG_PATH = "${llvmPkgs.libclang.lib}/lib";
        };
      };
    };
}
